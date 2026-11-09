"""Speaker diarization for Takeaway's live transcript.

POST /v1/diarize takes one standalone audio chunk (multipart field `file`) and a
`session` id (the speech id). It returns who spoke when inside the chunk:

    {"duration": 5.0, "segments": [{"start": 0.0, "end": 2.4, "speaker": "S1"}]}

Chunks are short (about 5 s), so diarizing each one on its own would call
everybody "speaker 1". The service keeps a voiceprint (mean speaker embedding)
per speaker for each session and matches every chunk's speakers against them,
so `S1` stays the same voice for the whole speech. Sessions live in memory:
one replica, and a restart starts the numbering again.

Models (sherpa-onnx, CPU, no Hugging Face token): pyannote segmentation 3.0
and the WeSpeaker ResNet34 English speaker embedding, baked into the image.
"""

import os
import subprocess
import tempfile
import threading
import time
from collections import OrderedDict
from contextlib import asynccontextmanager

import numpy as np
import sherpa_onnx
from fastapi import FastAPI, File, Form, HTTPException, UploadFile

SAMPLE_RATE = 16000
MODEL_DIR = os.environ.get("MODEL_DIR", "/models")
NUM_THREADS = int(os.environ.get("NUM_THREADS", "1"))
# Cosine distance under which pyannote's local clusters merge (bigger = fewer speakers).
CLUSTER_THRESHOLD = float(os.environ.get("CLUSTER_THRESHOLD", "0.3"))
# Cosine similarity a chunk's speaker needs to match a known voiceprint.
MATCH_THRESHOLD = float(os.environ.get("MATCH_THRESHOLD", "0.7"))
# Shortest speech (s) we trust for a voiceprint; shorter speakers reuse the best match.
MIN_EMBED_SECONDS = float(os.environ.get("MIN_EMBED_SECONDS", "0.8"))
MAX_SESSIONS = int(os.environ.get("MAX_SESSIONS", "200"))
SESSION_TTL = float(os.environ.get("SESSION_TTL_SECONDS", str(6 * 3600)))
MAX_UPLOAD_BYTES = 8_000_000


def _diarizer():
    config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
        segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
            pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
                model=os.path.join(MODEL_DIR, "segmentation.onnx")
            ),
            num_threads=NUM_THREADS,
        ),
        embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(
            model=os.path.join(MODEL_DIR, "embedding.onnx"), num_threads=NUM_THREADS
        ),
        clustering=sherpa_onnx.FastClusteringConfig(
            num_clusters=-1, threshold=CLUSTER_THRESHOLD
        ),
        min_duration_on=0.3,
        min_duration_off=0.5,
    )
    if not config.validate():
        raise RuntimeError("invalid diarization config (models missing?)")
    return sherpa_onnx.OfflineSpeakerDiarization(config)


def _extractor():
    config = sherpa_onnx.SpeakerEmbeddingExtractorConfig(
        model=os.path.join(MODEL_DIR, "embedding.onnx"), num_threads=NUM_THREADS
    )
    if not config.validate():
        raise RuntimeError("invalid embedding config (model missing?)")
    return sherpa_onnx.SpeakerEmbeddingExtractor(config)


class Sessions:
    """Per-session voiceprints: name -> (sum of unit embeddings, count)."""

    def __init__(self):
        self._data = OrderedDict()
        self._lock = threading.Lock()

    def match(self, session, embeddings):
        """Map each local speaker embedding (or None) to a stable name like "S1"."""
        with self._lock:
            self._expire()
            state = self._data.pop(session, None) or {"prints": {}, "next": 1}
            state["seen"] = time.monotonic()
            self._data[session] = state
            while len(self._data) > MAX_SESSIONS:
                self._data.popitem(last=False)
            return [self._assign(state, e) for e in embeddings]

    def _assign(self, state, emb):
        prints = state["prints"]
        best, best_sim = None, -1.0
        if emb is not None:
            for name, (total, _count) in prints.items():
                sim = float(np.dot(emb, total / np.linalg.norm(total)))
                if sim > best_sim:
                    best, best_sim = name, sim

        if emb is None:
            # Too little speech to tell: fall back to the most recent speaker, if any.
            return state.get("last") or self._new(state, None)
        if best is not None and best_sim >= MATCH_THRESHOLD:
            total, count = prints[best]
            prints[best] = (total + emb, count + 1)
            state["last"] = best
            return best
        return self._new(state, emb)

    def _new(self, state, emb):
        name = f"S{state['next']}"
        state["next"] += 1
        if emb is not None:
            state["prints"][name] = (emb.copy(), 1)
        state["last"] = name
        return name

    def _expire(self):
        cutoff = time.monotonic() - SESSION_TTL
        for key in [k for k, v in self._data.items() if v["seen"] < cutoff]:
            del self._data[key]


def decode(audio: bytes) -> np.ndarray:
    """Any container/codec ffmpeg reads -> 16 kHz mono float32."""
    with tempfile.NamedTemporaryFile(suffix=".audio") as f:
        f.write(audio)
        f.flush()
        proc = subprocess.run(
            ["ffmpeg", "-nostdin", "-loglevel", "error", "-i", f.name,
             "-f", "f32le", "-ac", "1", "-ar", str(SAMPLE_RATE), "pipe:1"],
            capture_output=True,
            timeout=30,
        )
    if proc.returncode != 0:
        raise ValueError(proc.stderr.decode(errors="replace").strip() or "ffmpeg failed")
    return np.frombuffer(proc.stdout, dtype=np.float32)


_lock = threading.Lock()  # sherpa-onnx objects are used from one thread at a time
_sd = None
_ex = None
_sessions = Sessions()


def _load():
    global _sd, _ex
    _sd = _diarizer()
    _ex = _extractor()


@asynccontextmanager
async def _lifespan(_app):
    _load()
    yield


app = FastAPI(title="takeaway-diarizer", lifespan=_lifespan)


@app.get("/health")
def health():
    return {"status": "ok" if _sd is not None else "loading"}


def _embedding(samples, spans):
    """Unit-length voiceprint from one local speaker's spans, or None if too short."""
    pieces = [samples[int(s * SAMPLE_RATE):int(e * SAMPLE_RATE)] for s, e in spans]
    audio = np.concatenate(pieces) if pieces else np.zeros(0, dtype=np.float32)
    if len(audio) < MIN_EMBED_SECONDS * SAMPLE_RATE:
        return None
    stream = _ex.create_stream()
    stream.accept_waveform(sample_rate=SAMPLE_RATE, waveform=audio)
    stream.input_finished()
    emb = np.array(_ex.compute(stream), dtype=np.float32)
    norm = np.linalg.norm(emb)
    return emb / norm if norm > 0 else None


def diarize(samples: np.ndarray, session: str):
    duration = len(samples) / SAMPLE_RATE
    if duration < 0.3:
        return {"duration": duration, "segments": []}

    with _lock:
        local = _sd.process(samples).sort_by_start_time()
        spans = {}
        for seg in local:
            spans.setdefault(seg.speaker, []).append((seg.start, seg.end))
        # New speakers get numbers in the order they first talk.
        ids = sorted(spans, key=lambda i: spans[i][0][0])
        embeddings = [_embedding(samples, spans[i]) for i in ids]

    names = dict(zip(ids, _sessions.match(session, embeddings)))
    return {
        "duration": duration,
        "segments": [
            {"start": round(s.start, 3), "end": round(s.end, 3), "speaker": names[s.speaker]}
            for s in local
        ],
    }


@app.post("/v1/diarize")
def diarize_endpoint(file: UploadFile = File(...), session: str = Form("default")):
    audio = file.file.read(MAX_UPLOAD_BYTES + 1)
    if len(audio) > MAX_UPLOAD_BYTES:
        raise HTTPException(413, "audio chunk too large")
    try:
        samples = decode(audio)
    except (ValueError, subprocess.TimeoutExpired) as e:
        raise HTTPException(400, f"could not decode audio: {e}")
    return diarize(samples, session[:128])
