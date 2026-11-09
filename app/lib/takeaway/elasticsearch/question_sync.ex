defmodule Takeaway.Elasticsearch.QuestionSync do
  @moduledoc """
  Supervised worker that subscribes to global question events (`questions:all`)
  and synchronizes questions to Elasticsearch on creation and retraction.
  """

  use GenServer
  require Logger

  alias Takeaway.Elasticsearch
  alias Takeaway.Questions

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    es_config = Application.get_env(:takeaway, :elasticsearch, [])

    auto_sync =
      Keyword.get(
        opts,
        :auto_sync,
        Keyword.get(es_config, :auto_sync, Application.get_env(:takeaway, :env) != :test)
      )

    if auto_sync do
      Questions.subscribe_global()
      Logger.info("[Elasticsearch.QuestionSync] Subscribed to #{Questions.global_topic()}")
    end

    {:ok, %{auto_sync: auto_sync}}
  end

  @impl true
  def handle_info({:question_created, question}, state) do
    case Elasticsearch.index_question(question) do
      {:ok, _} ->
        Logger.debug("[Elasticsearch.QuestionSync] Indexed question: #{question.id}")

      {:error, reason} ->
        Logger.warning(
          "[Elasticsearch.QuestionSync] Failed to index question #{question.id}: #{inspect(reason)}"
        )
    end

    {:noreply, state}
  rescue
    e ->
      Logger.warning("[Elasticsearch.QuestionSync] Exception indexing question: #{inspect(e)}")
      {:noreply, state}
  end

  @impl true
  def handle_info({:question_retracted, question}, state) do
    case Elasticsearch.delete_question(question.id) do
      {:ok, _} ->
        Logger.debug("[Elasticsearch.QuestionSync] Deleted retracted question: #{question.id}")

      {:error, reason} ->
        Logger.warning(
          "[Elasticsearch.QuestionSync] Failed to delete retracted question #{question.id}: #{inspect(reason)}"
        )
    end

    {:noreply, state}
  rescue
    e ->
      Logger.warning("[Elasticsearch.QuestionSync] Exception deleting question: #{inspect(e)}")
      {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
