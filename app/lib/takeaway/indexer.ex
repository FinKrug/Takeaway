defmodule Takeaway.Indexer do
  @moduledoc """
  Hand-off point for the Elasticsearch indexer. Every persisted transcript
  segment is passed to `index_segment/1`, and every stored slide (see
  `Takeaway.Slides`) to `index_slide/1`. The implementation is configured with
  `config :takeaway, :indexer, MyModule` (default: `Takeaway.Indexer.Noop`;
  `config/config.exs` sets `Takeaway.Elasticsearch.Indexer`).
  """
  @callback index_segment(segment :: struct()) :: :ok | {:error, term()}

  @doc """
  `slide` is a map with `:speech_id`, `:slide_number`, `:title` and `:content`
  (the shape of the Elasticsearch `slides` index).
  """
  @callback index_slide(slide :: map()) :: :ok | {:error, term()}

  def index_segment(segment), do: impl().index_segment(segment)
  def index_slide(slide), do: impl().index_slide(slide)
  def impl, do: Application.get_env(:takeaway, :indexer, Takeaway.Indexer.Noop)
end

defmodule Takeaway.Indexer.Noop do
  @moduledoc false
  @behaviour Takeaway.Indexer
  @impl true
  def index_segment(_segment), do: :ok
  @impl true
  def index_slide(_slide), do: :ok
end
