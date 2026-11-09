defmodule TakeawayWeb.SpeechLive.Show do
  @moduledoc "Speaker's speech page with live question groups and transcript."
  use TakeawayWeb, :live_view

  alias Takeaway.{Speeches, SpeechCreator, Summaries, Transcripts, Questions}
  alias TakeawayWeb.SpeakerLive

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    speech = Speeches.get_speech_by_join_code(code)
    organizer = socket.assigns.current_organizer

    # Missing and foreign speeches look the same.
    case speech && Takeaway.Organizers.owns_speech?(organizer, speech) && speech do
      falsy when falsy in [nil, false] ->
        {:ok,
         socket |> put_flash(:error, "Speech not found") |> push_navigate(to: ~p"/speeches/new")}

      speech ->
        if connected?(socket) do
          SpeechCreator.subscribe(speech.id)
          Transcripts.subscribe(speech.id)
          Questions.subscribe(speech.id)
        end

        {:ok,
         socket
         |> assign(:page_title, speech.title)
         |> assign(:speech, speech)
         |> assign(:artifacts, Speeches.list_artifacts(speech.id))
         |> assign(:summary, nil)
         |> assign(:summary_locked, false)
         |> stream_segments(initial_segments(speech))
         |> refresh_groups()
         |> load_summary()}
    end
  end

  # Render from started_at on load, not only from the broadcast.
  defp initial_segments(%{started_at: %DateTime{}} = speech),
    do: Transcripts.list_segments(speech.id)

  defp initial_segments(_speech), do: []

  defp stream_segments(socket, segments) do
    {segments, last} = TakeawayWeb.SpeakerLive.mark_turns(segments)
    socket |> assign(:last_speaker, last) |> stream(:segments, segments)
  end

  # Generates (once) or loads the cached speaker summary after the speech ended.
  defp load_summary(%{assigns: %{speech: %{ended_at: %DateTime{} = _}}} = socket) do
    speech = socket.assigns.speech

    if Summaries.allowed?(speech) do
      load_allowed_summary(socket, speech)
    else
      assign(socket, :summary_locked, true)
    end
  end

  defp load_summary(socket), do: socket

  defp load_allowed_summary(socket, speech) do
    case Summaries.get_speaker_summary(speech.id) do
      nil ->
        if connected?(socket),
          do: start_async(socket, :summary, fn -> Summaries.generate_on_end(speech) end),
          else: socket

      summary ->
        assign(socket, :summary, summary)
    end
  end

  @impl true
  def handle_async(:summary, {:ok, {:ok, summary}}, socket),
    do: {:noreply, assign(socket, :summary, summary)}

  def handle_async(:summary, {:ok, {:error, :plan_required}}, socket),
    do: {:noreply, assign(socket, :summary_locked, true)}

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

  def handle_info({:transcript_segment, seg}, socket),
    do: {:noreply, TakeawayWeb.SpeakerLive.insert_segment(socket, seg)}

  def handle_info({event, _}, socket)
      when event in [
             :question_created,
             :question_retracted,
             :question_groups_updated,
             :question_tagged,
             :question_answered
           ] do
    {:noreply, refresh_groups(socket)}
  end

  defp refresh_groups(socket) do
    stream(socket, :question_groups, Questions.list_top_groups(socket.assigns.speech.id),
      reset: true
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@speech.title}
        <:subtitle :if={@speech.description not in [nil, ""]}>{@speech.description}</:subtitle>

        <:actions>
          <.badge :if={is_nil(@speech.started_at)} tone="outline" id="speech-status">
            Not started
          </.badge>

          <.badge
            :if={@speech.started_at && is_nil(@speech.ended_at)}
            tone="danger"
            id="speech-status"
          >
            <.live_dot /> Live
          </.badge>

          <.badge :if={@speech.ended_at} tone="neutral" id="speech-status">Ended</.badge>
        </:actions>
      </.header>

      <div :if={@speech.tags != []} class="-mt-2 flex flex-wrap gap-2" id="speech-tags">
        <.badge :for={tag <- @speech.tags} tone="outline">#{tag}</.badge>
      </div>

      <.card tone="brand" id="join-info" class="text-center">
        <p class="text-sm font-medium text-muted">Attendees join with code</p>

        <p
          class="mt-1 font-mono text-[2.5rem] font-bold leading-none tracking-[0.2em] text-ink sm:text-5xl"
          id="join-code"
        >
          {@speech.join_code}
        </p>

        <p class="mt-3 break-all text-sm text-muted">
          or open
          <a
            class="font-semibold text-brand-strong underline-offset-4 hover:underline"
            id="join-link"
            href={~p"/join/#{@speech.join_code}"}
          >
            {url(~p"/join/#{@speech.join_code}")}
          </a>
        </p>
      </.card>

      <div class="flex flex-wrap gap-2" id="organizer-links">
        <.button
          href={~p"/speeches/#{@speech.id}/speak"}
          variant="secondary"
          size="sm"
          id="speak-link"
        >
          <.icon name="hero-microphone-mini" class="size-4" /> Speaker page (live transcript)
        </.button>

        <.button
          href={~p"/events/#{@speech.event_id}/tickets"}
          variant="secondary"
          size="sm"
          id="tickets-link"
        >
          <.icon name="hero-ticket-mini" class="size-4" /> Manage tickets
        </.button>
        <.button href={~p"/organizers"} variant="ghost" size="sm">Your events</.button>
      </div>

      <.card :if={@artifacts != []} title="Materials" id="artifacts">
        <ul class="-my-1 divide-y divide-line">
          <li :for={a <- @artifacts}>
            <a
              href={~p"/artifacts/#{a.id}"}
              class="group flex items-center gap-3 py-2.5 text-sm"
            >
              <.icon name="hero-document-text" class="size-5 shrink-0 text-muted" />
              <span class="min-w-0 flex-1 truncate font-medium group-hover:text-brand-strong">
                {a.title}
              </span>

              <.badge tone="outline">{a.kind}</.badge>
            </a>
          </li>
        </ul>
      </.card>

      <.button
        :if={is_nil(@speech.started_at)}
        id="start-speech"
        phx-click="start"
        size="lg"
        class="w-full"
      >
        <.icon name="hero-play-solid" class="size-5" /> Start Speech
      </.button>

      <.button
        :if={@speech.started_at && is_nil(@speech.ended_at)}
        id="end-speech"
        phx-click="end"
        data-confirm="End this speech?"
        variant="danger"
        size="lg"
        class="w-full"
      >
        <.icon name="hero-stop-solid" class="size-5" /> End Speech
      </.button>

      <.card :if={@speech.ended_at} id="speaker-summary" title="Speech summary">
        <p
          :if={@summary_locked}
          id="summary-locked"
          class="flex items-start gap-2 rounded-xl bg-warning-soft px-3.5 py-2.5 text-sm"
        >
          <.icon name="hero-lock-closed-mini" class="mt-0.5 size-4 shrink-0 text-warning" />
          Summaries are not included in your plan. Upgrade to get post-talk summaries.
        </p>

        <p
          :if={is_nil(@summary) and not @summary_locked}
          id="summary-loading"
          class="flex items-center gap-2 text-sm text-muted"
        >
          <.spinner /> Generating summary...
        </p>

        <div :if={@summary} class="space-y-6 motion-safe:animate-enter">
          <p id="summary-text" class="whitespace-pre-line text-pretty leading-relaxed">
            {@summary.content["summary"]}
          </p>

          <div id="summary-groups">
            <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-muted">
              Top questions
            </h3>

            <p :if={@summary.content["question_groups"] == []} class="text-sm text-muted">
              No questions were asked.
            </p>

            <ul class="space-y-2">
              <li :for={g <- @summary.content["question_groups"]} class="flex items-start gap-3">
                <.badge tone="brand" class="mt-0.5 tabular-nums">{g["count"]}</.badge>
                <span>{g["label"]}</span>
              </li>
            </ul>
          </div>

          <div id="summary-spikes">
            <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-muted">
              When questions spiked
            </h3>

            <p :if={@summary.content["question_spikes"] == []} class="text-sm text-muted">
              No clear spike in questions.
            </p>

            <ul class="space-y-1.5">
              <li :for={sp <- @summary.content["question_spikes"]} class="flex gap-3 text-sm">
                <span class="font-mono tabular-nums text-muted">
                  {format_ms(sp["start_ms"])} - {format_ms(sp["end_ms"])}
                </span>
                <span>{sp["count"]} questions</span>
              </li>
            </ul>
          </div>
        </div>
      </.card>

      <div
        :if={@speech.started_at && is_nil(@speech.ended_at)}
        id="live-panels"
        class="grid grid-cols-1 gap-4 lg:grid-cols-2"
      >
        <.card id="leaderboard-panel" title="Live question leaderboard">
          <p class="mb-3 text-sm text-muted">
            Similar questions are grouped. Most asked comes first.
          </p>

          <div id="question-leaderboard" phx-update="stream" class="space-y-3">
            <p id="leaderboard-empty" class="hidden only:block text-sm text-muted">
              Questions from attendees will appear here.
            </p>

            <div
              :for={{id, group} <- @streams.question_groups}
              id={id}
              class="flex items-start gap-3 rounded-xl border border-line bg-surface p-3 motion-safe:animate-enter"
            >
              <.badge tone="brand" class="shrink-0 tabular-nums">{group.count}</.badge>

              <p class="min-w-0 break-words text-sm font-medium text-ink">{group.text}</p>
            </div>
          </div>
        </.card>

        <.card id="transcript-panel" title="Live transcript">
          <SpeakerLive.transcript_list
            id="panel-transcript"
            segments={@streams.segments}
            class="max-h-80 overflow-y-auto text-sm"
          >
            <:empty>
              The transcript will appear here once the speaker starts talking.
            </:empty>
          </SpeakerLive.transcript_list>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  defp format_ms(ms), do: TakeawayWeb.SpeakerLive.format_ms(ms)
end
