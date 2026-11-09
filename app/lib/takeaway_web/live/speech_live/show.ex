defmodule TakeawayWeb.SpeechLive.Show do
  @moduledoc "Speaker's speech page: Start Speech button, join link/code, leaderboard placeholder."
  use TakeawayWeb, :live_view

  alias Takeaway.{Speeches, SpeechCreator, Summaries}

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    case Speeches.get_speech_by_join_code(code) do
      nil ->
        {:ok,
         socket |> put_flash(:error, "Speech not found") |> push_navigate(to: ~p"/speeches/new")}

      speech ->
        if connected?(socket), do: SpeechCreator.subscribe(speech.id)

        {:ok,
         socket
         |> assign(:page_title, speech.title)
         |> assign(:speech, speech)
         |> assign(:artifacts, Speeches.list_artifacts(speech.id))
         |> assign(:summary, nil)
         |> load_summary()}
    end
  end

  # Generates (once) or loads the cached speaker summary after the speech ended.
  defp load_summary(%{assigns: %{speech: %{ended_at: %DateTime{} = _}}} = socket) do
    speech = socket.assigns.speech

    case Summaries.get_speaker_summary(speech.id) do
      nil ->
        if connected?(socket),
          do: start_async(socket, :summary, fn -> Summaries.generate_on_end(speech) end),
          else: socket

      summary ->
        assign(socket, :summary, summary)
    end
  end

  defp load_summary(socket), do: socket

  @impl true
  def handle_async(:summary, {:ok, {:ok, summary}}, socket),
    do: {:noreply, assign(socket, :summary, summary)}

  def handle_async(:summary, _result, socket),
    do: {:noreply, put_flash(socket, :error, "Could not generate the summary")}

  @impl true
  def handle_event("start", _params, socket) do
    case SpeechCreator.start_speech(socket.assigns.speech) do
      {:ok, speech} -> {:noreply, assign(socket, :speech, speech)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not start the speech")}
    end
  end

  def handle_event("end", _params, socket) do
    case SpeechCreator.end_speech(socket.assigns.speech) do
      {:ok, speech} -> {:noreply, assign(socket, :speech, speech)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not end the speech")}
    end
  end

  @impl true
  def handle_info({:speech_ended, speech}, socket),
    do: {:noreply, socket |> assign(:speech, speech) |> load_summary()}

  def handle_info({:speech_started, speech}, socket) do
    {:noreply, assign(socket, :speech, speech)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-xl px-4 py-6 space-y-6">
        <.header>
          {@speech.title}
          <:subtitle>{@speech.description}</:subtitle>
        </.header>

        <div :if={@speech.tags != []} class="flex flex-wrap gap-2" id="speech-tags">
          <span :for={tag <- @speech.tags} class="badge badge-outline">{tag}</span>
        </div>

        <div class="card bg-base-200 p-4 space-y-1" id="join-info">
          <p class="text-sm">Attendees join with code</p>
          <p class="text-3xl font-mono font-bold tracking-widest" id="join-code">
            {@speech.join_code}
          </p>
          <p class="text-sm break-all">
            Link:
            <a class="link" id="join-link" href={~p"/join/#{@speech.join_code}"}>
              {url(~p"/join/#{@speech.join_code}")}
            </a>
          </p>
        </div>

        <ul :if={@artifacts != []} class="text-sm space-y-1" id="artifacts">
          <li :for={a <- @artifacts}>
            {a.kind}: <a class="link" href={~p"/artifacts/#{a.id}"}>{a.title}</a>
          </li>
        </ul>

        <button
          :if={is_nil(@speech.started_at)}
          id="start-speech"
          phx-click="start"
          class="btn btn-primary btn-lg w-full"
        >
          Start Speech
        </button>

        <button
          :if={@speech.started_at && is_nil(@speech.ended_at)}
          id="end-speech"
          phx-click="end"
          data-confirm="End this speech?"
          class="btn btn-error btn-lg w-full"
        >
          End Speech
        </button>

        <div :if={@speech.ended_at} id="speaker-summary" class="card bg-base-200 p-4 space-y-4">
          <h2 class="font-semibold text-lg">Speech summary</h2>
          <p :if={is_nil(@summary)} id="summary-loading" class="text-sm opacity-70">
            Generating summary...
          </p>
          <div :if={@summary} class="space-y-4">
            <p id="summary-text" class="whitespace-pre-line">{@summary.content["summary"]}</p>

            <div id="summary-groups">
              <h3 class="font-semibold">Top questions</h3>
              <p :if={@summary.content["question_groups"] == []} class="text-sm opacity-70">
                No questions were asked.
              </p>
              <ul class="space-y-1">
                <li :for={g <- @summary.content["question_groups"]}>
                  <span class="badge badge-neutral">{g["count"]}</span> {g["label"]}
                </li>
              </ul>
            </div>

            <div id="summary-spikes">
              <h3 class="font-semibold">When questions spiked</h3>
              <p :if={@summary.content["question_spikes"] == []} class="text-sm opacity-70">
                No clear spike in questions.
              </p>
              <ul class="space-y-1">
                <li :for={sp <- @summary.content["question_spikes"]}>
                  {format_ms(sp["start_ms"])} - {format_ms(sp["end_ms"])}: {sp["count"]} questions
                </li>
              </ul>
            </div>
          </div>
        </div>

        <div
          :if={@speech.started_at && is_nil(@speech.ended_at)}
          id="leaderboard-panel"
          class="card border border-dashed p-4"
        >
          <h2 class="font-semibold">Live question leaderboard</h2>
          <p class="text-sm opacity-70">Questions from attendees will appear here.</p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_ms(ms), do: TakeawayWeb.SpeakerLive.format_ms(ms)
end
