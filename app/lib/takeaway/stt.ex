defmodule Takeaway.STT do
  @moduledoc """
  Speech-to-text behaviour. `transcribe/3` takes one standalone audio chunk and
  returns segments with offsets (ms) relative to the start of that chunk.

  The implementation is chosen with `config :takeaway, :stt, MyModule`.
  """

  @type segment :: %{text: String.t(), start_ms: non_neg_integer(), end_ms: non_neg_integer()}

  @callback transcribe(audio :: binary(), content_type :: String.t(), opts :: keyword()) ::
              {:ok, [segment()]} | {:error, term()}

  def transcribe(audio, content_type, opts \\ []) do
    impl().transcribe(audio, content_type, opts)
  end

  def impl, do: Application.get_env(:takeaway, :stt, Takeaway.STT.Disabled)
end

defmodule Takeaway.STT.Disabled do
  @moduledoc "Used when no STT service is configured: returns no segments."
  @behaviour Takeaway.STT
  require Logger

  @impl true
  def transcribe(_audio, _content_type, _opts) do
    Logger.debug("STT not configured (set STT_URL); dropping audio chunk")
    {:ok, []}
  end
end
