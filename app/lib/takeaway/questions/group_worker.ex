defmodule Takeaway.Questions.GroupWorker do
  @moduledoc "Groups question events off the submission path. Duplicate delivery is safe."
  use GenServer
  require Logger
  alias Takeaway.Questions
  alias Takeaway.Questions.Grouping

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :enabled, Application.get_env(:takeaway, :question_grouping, true)) do
      Questions.subscribe_global()
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info({event, question}, state)
      when event in [:question_created, :question_retracted] do
    case event do
      :question_created -> Grouping.assign(question)
      :question_retracted -> Grouping.retract(question)
    end

    {:noreply, state}
  rescue
    error ->
      Logger.warning("Question grouping failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
