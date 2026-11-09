defmodule Takeaway.Indexer do
  @moduledoc """
  Hand-off point for the Elasticsearch indexer. Every persisted transcript
  segment is passed to `index_segment/1`. The implementation is configured with
  `config :takeaway, :indexer, MyModule` (default: `Takeaway.Indexer.Noop`).
  """
  @callback index_segment(segment :: struct()) :: :ok | {:error, term()}

  def index_segment(segment), do: impl().index_segment(segment)
  def impl, do: Application.get_env(:takeaway, :indexer, Takeaway.Indexer.Noop)
end

defmodule Takeaway.Indexer.Noop do
  @moduledoc false
  @behaviour Takeaway.Indexer
  @impl true
  def index_segment(_segment), do: :ok
end
