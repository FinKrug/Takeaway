# Speaker diarization service (see server.py). Build context: diarizer/.
FROM docker.io/python:3.12-slim-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg ca-certificates curl bzip2 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Models are baked in, so the pod needs no download or PVC at startup.
# pyannote segmentation 3.0 (MIT) and WeSpeaker ResNet34 English (Apache-2.0),
# both as published by sherpa-onnx. ("recongition" is the release tag's spelling.)
ARG SHERPA_RELEASES=https://github.com/k2-fsa/sherpa-onnx/releases/download
RUN mkdir -p /models \
 && curl -fsSL "$SHERPA_RELEASES/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2" \
    | tar xj -C /tmp \
 && mv /tmp/sherpa-onnx-pyannote-segmentation-3-0/model.onnx /models/segmentation.onnx \
 && rm -rf /tmp/sherpa-onnx-pyannote-segmentation-3-0 \
 && curl -fsSL -o /models/embedding.onnx \
    "$SHERPA_RELEASES/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx" \
 && apt-get purge -y curl bzip2 && apt-get autoremove -y

COPY server.py .

ENV MODEL_DIR=/models PYTHONUNBUFFERED=1
USER 1000
EXPOSE 8000
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
