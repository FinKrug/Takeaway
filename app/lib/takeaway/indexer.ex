defmodule Takeaway.Indexer do
  @moduledoc """
  Hand-off point for the Elasticsearch indexer. Every persisted transcript
  segment is passed to `index_segment/1`, and every stored slide (see
  `Takeaway.Slides`) to `index_slide/1`. The implementation is configured with
  `config :takeaway, :indexer, MyModule` (default: `Takeaway.Indexer.Noop`).
  `Takeaway.Indexer.Elasticsearch` sends slides to Elasticsearch once it is
  deployed.
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

defmodule Takeaway.Indexer.Elasticsearch do
  @moduledoc """
  Indexer backed by `Takeaway.Elasticsearch`. Slides go to the `slides` index
  (doc id `<speech_id>_<slide_number>`, so re-indexing overwrites). Transcript
  segments are not wired to Elasticsearch yet and are skipped.

  Enable with `config :takeaway, :indexer, Takeaway.Indexer.Elasticsearch`
  once Elasticsearch runs in the cluster.
  """
  @behaviour Takeaway.Indexer

  @impl true
  def index_segment(_segment), do: :ok

  @impl true
  def index_slide(slide) do
    case Takeaway.Elasticsearch.index_slide(slide) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end
