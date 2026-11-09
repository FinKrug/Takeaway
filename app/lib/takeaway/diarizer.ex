defmodule Takeaway.Diarizer do
  @moduledoc """
  Speaker diarization: who spoke when inside one audio chunk.

  `diarize/3` takes the same standalone chunk as `Takeaway.STT.transcribe/3`
  plus a `session` (the speech id) and returns speaker turns with offsets (ms)
  relative to the start of the chunk. The in-cluster service (`diarizer/`,
  `deploy/diarizer.yaml`) keeps a voiceprint per speaker per session, so a label
  such as `"S1"` means the same voice for the whole speech.

  `label/2` puts those speakers on transcript segments by time overlap.

  The implementation is chosen with `config :takeaway, :diarizer, MyModule`;
  `Takeaway.Diarizer.HTTP` is used when `DIARIZER_URL` is set.
  """

  @type turn :: %{start_ms: non_neg_integer(), end_ms: non_neg_integer(), speaker: String.t()}

  @callback diarize(audio :: binary(), content_type :: String.t(), session :: String.t()) ::
              {:ok, [turn()]} | {:error, term()}

  def diarize(audio, content_type, session) do
    impl().diarize(audio, content_type, to_string(session))
  end

  def impl, do: Application.get_env(:takeaway, :diarizer, Takeaway.Diarizer.Disabled)

  def enabled?, do: impl() != Takeaway.Diarizer.Disabled

  @doc """
  Gives each segment the speaker whose turns overlap it the most. Segments that
  already have a `:speaker` (from the STT provider) keep it; segments no turn
  overlaps are left without one.
  """
  def label(segments, []), do: segments

  def label(segments, turns) do
    Enum.map(segments, fn seg ->
      if Map.get(seg, :speaker), do: seg, else: put_speaker(seg, turns)
    end)
  end

  defp put_speaker(seg, turns) do
    turns
    |> Enum.reduce(%{}, fn t, acc ->
      overlap = min(seg.end_ms, t.end_ms) - max(seg.start_ms, t.start_ms)
      if overlap > 0, do: Map.update(acc, t.speaker, overlap, &(&1 + overlap)), else: acc
    end)
    |> Enum.max_by(fn {_speaker, ms} -> ms end, fn -> nil end)
    |> case do
      {speaker, _ms} -> Map.put(seg, :speaker, speaker)
      nil -> seg
    end
  end
end

defmodule Takeaway.Diarizer.Disabled do
  @moduledoc "Used when no diarizer is configured (set DIARIZER_URL): no speaker turns."
  @behaviour Takeaway.Diarizer

  @impl true
  def diarize(_audio, _content_type, _session), do: {:ok, []}
end

defmodule Takeaway.Diarizer.HTTP do
  @moduledoc """
  Client for the in-cluster diarizer's `POST /v1/diarize`. Configure with
  `config :takeaway, Takeaway.Diarizer.HTTP, url: ...`; tests can pass
  `req_options` (for example `plug: {Req.Test, ...}`).
  """
  @behaviour Takeaway.Diarizer

  @impl true
  def diarize(audio, content_type, session) do
    cfg = Application.get_env(:takeaway, __MODULE__, [])
    ext = if String.contains?(content_type, "ogg"), do: "ogg", else: "webm"

    req =
      Req.new(
        url: Keyword.fetch!(cfg, :url),
        receive_timeout: Keyword.get(cfg, :timeout, 15_000),
        retry: false
      )
      |> Req.merge(Keyword.get(cfg, :req_options, []))

    form = [
      session: session,
      file: {audio, filename: "chunk.#{ext}", content_type: content_type}
    ]

    case Req.post(req, form_multipart: form) do
      {:ok, %{status: 200, body: body}} -> parse(body)
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def parse(%{"segments" => segs}) when is_list(segs) do
    {:ok,
     for %{"start" => s, "end" => e, "speaker" => sp} <- segs,
         is_number(s) and is_number(e) and is_binary(sp) and sp != "" do
       %{start_ms: round(s * 1000), end_ms: round(e * 1000), speaker: sp}
     end}
  end

  def parse(_), do: {:error, :bad_response}
end
