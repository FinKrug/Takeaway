defmodule Takeaway.FakeSTT do
  @behaviour Takeaway.STT
  @impl true
  def transcribe("boom", _, _), do: {:error, :down}

  def transcribe(_audio, _type, _opts),
    do:
      {:ok,
       [%{text: "hello", start_ms: 0, end_ms: 800}, %{text: "world", start_ms: 800, end_ms: 1500}]}
end

defmodule Takeaway.FakeIndexer do
  @behaviour Takeaway.Indexer
  @impl true
  def index_segment(seg) do
    send(Application.fetch_env!(:takeaway, :indexer_test_pid), {:indexed, seg})
    :ok
  end
end
