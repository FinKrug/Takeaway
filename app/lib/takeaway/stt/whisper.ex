defmodule Takeaway.STT.Whisper do
  @moduledoc """
  OpenAI-compatible `/audio/transcriptions` client (OpenAI, faster-whisper-server,
  whisper.cpp server, ...). Configure with
  `config :takeaway, Takeaway.STT.Whisper, url: ..., api_key: ..., model: ...`.
  Requests `verbose_json` so segments carry start/end seconds.

  Speaker diarization is off by default; turn it on with `diarize: true` in the
  config (`STT_DIARIZE=true`) or per call, for a provider that supports it. When on,
  the request carries `diarize=true` and any `speaker` label the provider
  returns for a segment is passed through as `:speaker`.
  """
  @behaviour Takeaway.STT

  @impl true
  def transcribe(audio, content_type, opts) do
    cfg = Application.get_env(:takeaway, __MODULE__, [])
    url = Keyword.get(opts, :url) || Keyword.fetch!(cfg, :url)
    model = Keyword.get(opts, :model) || Keyword.get(cfg, :model, "whisper-1")
    boundary = "----takeaway" <> Base.encode16(:crypto.strong_rand_bytes(8))

    diarize = Keyword.get(opts, :diarize, Keyword.get(cfg, :diarize, false))
    body = multipart(boundary, audio, content_type, model, diarize)

    headers =
      case Keyword.get(cfg, :api_key) do
        nil -> []
        key -> [{~c"authorization", String.to_charlist("Bearer " <> key)}]
      end

    request =
      {String.to_charlist(url), headers,
       String.to_charlist("multipart/form-data; boundary=" <> boundary), body}

    case :httpc.request(:post, request, [timeout: 30_000], body_format: :binary) do
      {:ok, {{_, 200, _}, _, resp}} -> parse(resp)
      {:ok, {{_, status, _}, _, resp}} -> {:error, {:http, status, resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def parse(json) do
    case Jason.decode(json) do
      {:ok, %{"segments" => segs}} when is_list(segs) ->
        {:ok,
         for %{"text" => text, "start" => s, "end" => e} = seg <- segs, String.trim(text) != "" do
           base = %{text: String.trim(text), start_ms: round(s * 1000), end_ms: round(e * 1000)}

           case seg["speaker"] do
             sp when is_binary(sp) and sp != "" -> Map.put(base, :speaker, sp)
             _ -> base
           end
         end}

      {:ok, %{"text" => text} = m} when is_binary(text) ->
        case String.trim(text) do
          "" ->
            {:ok, []}

          t ->
            {:ok, [%{text: t, start_ms: 0, end_ms: round((m["duration"] || 0) * 1000)}]}
        end

      _ ->
        {:error, :bad_response}
    end
  end

  @doc false
  def multipart(boundary, audio, content_type, model, diarize \\ false) do
    ext = if String.contains?(content_type, "ogg"), do: "ogg", else: "webm"

    IO.iodata_to_binary([
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n#{model}\r\n",
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\nverbose_json\r\n",
      diarize_field(boundary, diarize),
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"chunk.#{ext}\"\r\n",
      "Content-Type: #{content_type}\r\n\r\n",
      audio,
      "\r\n--#{boundary}--\r\n"
    ])
  end

  defp diarize_field(boundary, true),
    do: "--#{boundary}\r\nContent-Disposition: form-data; name=\"diarize\"\r\n\r\ntrue\r\n"

  defp diarize_field(_boundary, _), do: ""
end
