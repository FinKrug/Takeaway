defmodule Takeaway.Questions.TagWorker do
  @moduledoc "Enriches questions off the submission path and handles delayed transcripts."
  use GenServer
  require Logger
  alias Takeaway.Questions.{Tagging, Question}

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :enabled, Application.get_env(:takeaway, :question_tagging, true)) do
      Takeaway.Questions.subscribe_global()
      Phoenix.PubSub.subscribe(Takeaway.PubSub, "transcripts:all")
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info({:question_created, %Question{id: id}}, state) do
    safely(fn -> Tagging.enrich(id) end)
    {:noreply, state}
  end

  def handle_info({:transcript_recorded, speech_id, segment}, state) do
    safely(fn -> Tagging.attach_delayed(speech_id, segment) end)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp safely(fun) do
    fun.()
  rescue
    error -> Logger.warning("Question tagging failed: #{Exception.message(error)}")
  catch
    kind, _ -> Logger.warning("Question tagging stopped: #{kind}")
  end
end
