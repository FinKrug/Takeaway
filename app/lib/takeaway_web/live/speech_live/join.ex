defmodule TakeawayWeb.SpeechLive.Join do
  @moduledoc """
  Attendee page for a join link/code (`/join/:code`).

  * Ticket gate and not-found states.
  * Waiting room until the speaker starts, live state, ended state with the attendee's
    cliffnotes. Start/end arrive over `SpeechCreator` PubSub, no reload needed.
  * Private notes for this speech (one per attendee), autosaved with a debounce.
  * Questions: everyone's questions streamed live (`Questions` PubSub), a form to ask one
    while the speech is live, and Retract on the attendee's own questions.
  * The speaker's current slide (`{:slide_changed, speech_id, n}` on the `SpeechCreator`
    topic) is shown and prefills the form's optional slide field, so questions are tagged
    with it. Once the attendee picks another slide (or clears it) their choice is kept.
  * On phones Notes and Questions are two client-side tabs; from `md:` side by side.

  The attendee is the anonymous user whose id `TakeawayWeb.AttendeeSession` stores as
  `"user_id"` in the session. Without one (cookies blocked, crawlers) the page is read-only.
  """
  use TakeawayWeb, :live_view

  alias Takeaway.{
    Accounts,
    Notes,
    Questions,
    Slides,
    Speeches,
    SpeechCreator,
    Summaries,
    Tickets,
    Transcripts
  }

  alias Takeaway.Accounts.User
  alias Takeaway.Notes.Note

  @max_question_length 500
  # Simple per-attendee rate limit for questions.
  @question_interval_ms 5_000
  @question_types %{text: :string, slide_number: :integer}

  @impl true
  def mount(%{"code" => code} = params, session, socket) do
    socket = base_assigns(socket)

    case Speeches.get_speech_by_join_code(code) do
      nil ->
        {:ok, socket}

      speech ->
        case Tickets.validate_for_event(speech.event_id, params["ticket"]) do
          :ok -> mount_attendee(speech, session, socket)
          {:error, reason} -> {:ok, gate(socket, reason)}
        end
    end
  end

  # Defaults for every state, so the not-found and gated pages render too.
  defp base_assigns(socket) do
    socket
    |> assign(
      speech: nil,
      speaker_name: nil,
      page_title: "Join",
      user: nil,
      user_id: nil,
      summary: nil,
      summary_locked: false,
      ticket_error: nil,
      note_form: to_form(Note.changeset(%Note{}, %{})),
      note_status: :idle,
      question_form: question_form(%{}),
      slide_count: 0,
      current_slide: nil,
      question_ids: MapSet.new(),
      my_question_ids: MapSet.new(),
      last_question_at: nil,
      last_speaker: nil
    )
    |> stream(:segments, [])
    |> stream_configure(:questions, dom_id: &"question-#{&1.id}")
    |> stream(:questions, [])
  end

  # Ticket missing or invalid: show the gate, never the speech or its updates.
  defp gate(socket, reason), do: assign(socket, ticket_error: reason)

  defp mount_attendee(speech, session, socket) do
    if connected?(socket) do
      SpeechCreator.subscribe(speech.id)
      Questions.subscribe(speech.id)
      Transcripts.subscribe(speech.id)
    end

    user = session_attendee(session)
    user_id = user && user.id
    note = (user && Notes.get_note_for(speech.id, user.id)) || %Note{}

    # Re-read on every mount, so a reconnect catches up on anything missed.
    questions = Questions.list_questions(speech.id)
    slide_count = Slides.count_slides(speech.id)
    current_slide = SpeechCreator.current_slide(speech, slide_count)

    {:ok,
     socket
     |> assign(
       speech: speech,
       speaker_name: speaker_name(speech),
       page_title: speech.title,
       user: user,
       user_id: user_id,
       note_form: to_form(Note.changeset(note, %{})),
       note_status: if(note.id, do: :saved, else: :idle),
       slide_count: slide_count,
       current_slide: current_slide,
       question_form: question_form(slide_params(current_slide)),
       question_ids: MapSet.new(questions, & &1.id),
       my_question_ids:
         questions |> Enum.filter(&(user_id && &1.user_id == user_id)) |> MapSet.new(& &1.id)
     )
     |> stream(:questions, Enum.map(questions, &item(&1, false)), reset: true)
     |> load_captions(speech)
     |> load_summary()}
  end

  # Live captions (WCAG 1.2.4): the speaker's live transcript, shown only while the talk runs.
  defp load_captions(socket, %{started_at: %DateTime{}, ended_at: nil} = speech) do
    {segments, last} = TakeawayWeb.SpeakerLive.mark_turns(Transcripts.list_segments(speech.id))
    socket |> assign(:last_speaker, last) |> stream(:segments, segments, reset: true)
  end

  defp load_captions(socket, _speech), do: socket

  defp session_attendee(%{"user_id" => id}) when is_integer(id) do
    case Accounts.get_user(id) do
      %User{role: "attendee"} = user -> user
      _ -> nil
    end
  end

  defp session_attendee(_session), do: nil

  defp speaker_name(%{speaker_id: nil}), do: nil

  defp speaker_name(%{speaker_id: id}) do
    case Accounts.get_user(id) do
      %User{name: name} when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  # Stream entries carry `fresh?` so only questions arriving live animate in.
  defp item(question, fresh?), do: %{id: question.id, question: question, fresh?: fresh?}

  defp track_question(socket, question) do
    mine? = socket.assigns.user_id != nil and question.user_id == socket.assigns.user_id

    socket = update(socket, :question_ids, &MapSet.put(&1, question.id))

    if mine?,
      do: update(socket, :my_question_ids, &MapSet.put(&1, question.id)),
      else: socket
  end

  defp untrack_question(socket, question) do
    socket
    |> update(:question_ids, &MapSet.delete(&1, question.id))
    |> update(:my_question_ids, &MapSet.delete(&1, question.id))
  end

  # After the speech ended, show this attendee's cliffnotes (generated once, cached).
  defp load_summary(%{assigns: %{speech: %{ended_at: %DateTime{}}, user_id: uid}} = socket)
       when not is_nil(uid) do
    speech = socket.assigns.speech

    if Summaries.allowed?(speech) do
      load_allowed_summary(socket, speech, uid)
    else
      assign(socket, :summary_locked, true)
    end
  end

  defp load_summary(socket), do: socket

  defp load_allowed_summary(socket, speech, uid) do
    case Summaries.get_attendee_summary(speech.id, uid) do
      nil ->
        if connected?(socket),
          do: start_async(socket, :summary, fn -> Summaries.attendee_summary(speech, uid) end),
          else: socket

      summary ->
        assign(socket, :summary, summary)
    end
  end

  defp max_question_length, do: @max_question_length

  defp questions_open?(%{started_at: %DateTime{}, ended_at: nil}), do: true
  defp questions_open?(_speech), do: false

  ## Questions form

  defp question_changeset(params) do
    {%{}, @question_types}
    |> Ecto.Changeset.cast(params, Map.keys(@question_types))
    |> Ecto.Changeset.validate_required([:text], message: "type a question first")
    |> Ecto.Changeset.validate_length(:text, max: @max_question_length)
    |> Ecto.Changeset.validate_number(:slide_number, greater_than: 0)
  end

  defp question_form(params, action \\ nil) do
    params
    |> question_changeset()
    |> Map.put(:action, action)
    |> to_form(as: :question)
  end

  # Prefills the optional slide field with the speaker's current slide.
  defp slide_params(nil), do: %{}
  defp slide_params(n), do: %{"slide_number" => n}

  defp question_error(socket, params, message) do
    form =
      params
      |> question_changeset()
      |> Ecto.Changeset.add_error(:text, message)
      |> Map.put(:action, :insert)
      |> to_form(as: :question)

    assign(socket, :question_form, form)
  end

  defp rate_limited?(%{assigns: %{last_question_at: nil}}), do: false

  defp rate_limited?(%{assigns: %{last_question_at: at}}),
    do: System.monotonic_time(:millisecond) - at < @question_interval_ms

  defp submit_question(socket, params) do
    %{speech: speech, user: user} = socket.assigns

    with {:ok, data} <- Ecto.Changeset.apply_action(question_changeset(params), :insert),
         {:ok, question} <-
           Questions.submit_question(speech, user, %{
             "text" => data.text,
             "slide_number" => data[:slide_number]
           }) do
      socket
      |> track_question(question)
      |> stream_insert(:questions, item(question, true))
      |> assign(
        question_form: question_form(slide_params(socket.assigns.current_slide)),
        last_question_at: System.monotonic_time(:millisecond)
      )
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, :question_form, to_form(changeset, as: :question))

      {:error, reason} ->
        question_error(socket, params, filter_message(reason))
    end
  end

  defp filter_message(reason) when is_binary(reason), do: reason
  defp filter_message(_reason), do: "this question can't be posted"

  ## Events

  @impl true
  def handle_event("save_note", %{"note" => %{"body" => body}}, %{assigns: %{user: %User{}}} = s) do
    case Notes.save_note(s.assigns.speech.id, s.assigns.user.id, body) do
      {:ok, note} ->
        {:noreply, assign(s, note_form: to_form(Note.changeset(note, %{})), note_status: :saved)}

      {:error, changeset} ->
        {:noreply, assign(s, note_form: to_form(changeset), note_status: :error)}
    end
  end

  def handle_event("save_note", _params, socket), do: {:noreply, socket}

  def handle_event("validate_question", %{"question" => params}, socket),
    do: {:noreply, assign(socket, :question_form, question_form(params, :validate))}

  def handle_event("submit_question", %{"question" => params}, socket) do
    cond do
      is_nil(socket.assigns.user) ->
        {:noreply, question_error(socket, params, "turn on cookies to ask questions")}

      not questions_open?(socket.assigns.speech) ->
        {:noreply, question_error(socket, params, "questions are open while the speech is live")}

      rate_limited?(socket) ->
        {:noreply, question_error(socket, params, "wait a few seconds before asking again")}

      true ->
        {:noreply, submit_question(socket, params)}
    end
  end

  def handle_event("retract", %{"id" => id}, socket) do
    with %User{} = user <- socket.assigns.user,
         {id, ""} <- Integer.parse(to_string(id)),
         {:ok, question} <- Questions.retract_question_by(id, user) do
      {:noreply,
       socket |> untrack_question(question) |> stream_delete(:questions, item(question, false))}
    else
      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can only retract your own questions")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not retract that question")}
    end
  end

  @impl true
  def handle_async(:summary, {:ok, {:ok, summary}}, socket),
    do: {:noreply, assign(socket, :summary, summary)}

  def handle_async(:summary, {:ok, {:error, :plan_required}}, socket),
    do: {:noreply, assign(socket, :summary_locked, true)}

  def handle_async(:summary, _result, socket),
    do: {:noreply, put_flash(socket, :error, "Could not generate your summary")}

  @impl true
  def handle_info({:speech_started, speech}, socket),
    do: {:noreply, assign(socket, :speech, speech)}

  def handle_info({:speech_ended, speech}, socket),
    do: {:noreply, socket |> assign(:speech, speech) |> load_summary()}

  # Upsert by DOM id, so a duplicate broadcast updates instead of duplicating.
  def handle_info({:question_created, question}, socket) do
    {:noreply,
     socket |> track_question(question) |> stream_insert(:questions, item(question, true))}
  end

  def handle_info({:question_retracted, question}, socket) do
    {:noreply,
     socket |> untrack_question(question) |> stream_delete(:questions, item(question, false))}
  end

  def handle_info({event, question}, socket)
      when event in [:question_answered, :question_tagged] do
    if MapSet.member?(socket.assigns.question_ids, question.id),
      do: {:noreply, stream_insert(socket, :questions, item(question, false))},
      else: {:noreply, socket}
  end

  # The form's slide follows the speaker unless the attendee changed it (keeps the text).
  def handle_info({:slide_changed, id, n}, %{assigns: %{speech: %{id: id}}} = socket)
      when is_integer(n) do
    # Slides may have been extracted since mount; never show a slide past a known deck.
    count =
      case socket.assigns.slide_count do
        0 -> Slides.count_slides(id)
        known -> known
      end

    n = SpeechCreator.current_slide(%{current_slide: n}, count)
    %{current_slide: old, question_form: form} = socket.assigns
    follows? = to_string(form.params["slide_number"]) == to_string(old)

    socket =
      if follows? do
        params = Map.put(form.params, "slide_number", n)
        assign(socket, :question_form, question_form(params, form.source.action))
      else
        socket
      end

    {:noreply, assign(socket, slide_count: count, current_slide: n)}
  end

  def handle_info({:transcript_segment, seg}, socket),
    do: {:noreply, TakeawayWeb.SpeakerLive.insert_segment(socket, seg)}

  # Anything else on the speech topics (future events) is ignored, never a crash.
  def handle_info(_message, socket), do: {:noreply, socket}

  ## Rendering

  # Client-side tab switch (no server round trip); both panels stay mounted.
  defp select_tab(tab) do
    other = if tab == "notes", do: "questions", else: "notes"

    JS.remove_class("hidden", to: "#panel-#{tab}")
    |> JS.add_class("hidden", to: "#panel-#{other}")
    |> JS.set_attribute({"aria-selected", "true"}, to: "#tab-#{tab}")
    |> JS.set_attribute({"aria-selected", "false"}, to: "#tab-#{other}")
    |> JS.set_attribute({"tabindex", "0"}, to: "#tab-#{tab}")
    |> JS.set_attribute({"tabindex", "-1"}, to: "#tab-#{other}")
  end

  attr :id, :string, required: true
  attr :controls, :string, required: true
  attr :selected, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  defp tab(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      role="tab"
      aria-selected={to_string(@selected)}
      tabindex={if @selected, do: "0", else: "-1"}
      aria-controls={@controls}
      class={[
        "inline-flex h-11 items-center justify-center gap-2 rounded-xl text-sm font-semibold text-muted",
        "transition-[background-color,color,box-shadow] duration-150",
        "aria-selected:bg-surface aria-selected:text-ink aria-selected:shadow-sm aria-selected:shadow-black/5",
        "focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-brand/15"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp notice(assigns) do
    ~H"""
    <p id={@id} class="flex items-start gap-2 rounded-xl bg-sunken px-3.5 py-2.5 text-sm text-muted">
      <.icon name={@icon} class="mt-0.5 size-4 shrink-0" /> {render_slot(@inner_block)}
    </p>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide={not is_nil(@speech)}>
      <.empty_state
        :if={@ticket_error == :ticket_required}
        id="join-ticket-required"
        icon="hero-ticket"
        title="This event needs a ticket"
      >
        A ticket code is required to join this event. Add ?ticket=YOURCODE to the link.
      </.empty_state>

      <.empty_state
        :if={@ticket_error == :invalid_ticket}
        id="join-ticket-invalid"
        icon="hero-ticket"
        title="Ticket not recognized"
      >
        That ticket code is not valid for this event.
      </.empty_state>

      <.empty_state
        :if={is_nil(@speech) && is_nil(@ticket_error)}
        id="join-not-found"
        icon="hero-magnifying-glass"
        title="No speech found for that code."
      >
        Check the code on the speaker's slide and try again.
        <:actions>
          <.button navigate={~p"/#join"} variant="secondary">Enter another code</.button>
        </:actions>
      </.empty_state>

      <div :if={@speech} class="space-y-6">
        <.header>
          {@speech.title}
          <:subtitle :if={@speaker_name}>by {@speaker_name}</:subtitle>
        </.header>

        <div id="speech-status" role="status" aria-live="polite">
          <.card
            :if={is_nil(@speech.started_at)}
            id="join-waiting"
            tone="sunken"
            class="flex items-center gap-3"
          >
            <span class="text-warning"><.live_dot class="size-2.5" /></span>
            <div>
              <p class="font-medium">Waiting for the speaker to start...</p>
              <p class="text-sm text-muted">
                The speech starts soon. You can already take notes.
              </p>
            </div>
          </.card>

          <.card
            :if={@speech.started_at && is_nil(@speech.ended_at)}
            id="join-live"
            tone="brand"
            class="flex items-center gap-3"
          >
            <span class="text-danger"><.live_dot class="size-2.5" /></span>
            <p class="font-medium">The speech is live.</p>
            <.badge :if={@current_slide} id="join-current-slide" tone="outline" class="ml-auto">
              Slide {@current_slide}
            </.badge>
          </.card>

          <.card :if={@speech.ended_at} id="join-ended" tone="sunken" class="flex items-center gap-3">
            <.icon name="hero-check-circle" class="size-5 text-success" />
            <p class="font-medium">The speech has ended.</p>
          </.card>
        </div>

        <.card
          :if={@speech.started_at && is_nil(@speech.ended_at)}
          id="live-captions"
          title="Live captions"
        >
          <div id="live-captions-log" role="log" aria-live="off" aria-label="Live captions">
            <TakeawayWeb.SpeakerLive.transcript_list id="captions" segments={@streams.segments}>
              <:empty>Captions appear here a few seconds after the speaker starts talking.</:empty>
            </TakeawayWeb.SpeakerLive.transcript_list>
          </div>
        </.card>

        <.card :if={@speech.ended_at && @user_id} id="attendee-summary" title="Your cliffnotes">
          <p
            :if={@summary_locked}
            id="summary-locked"
            class="flex items-start gap-2 rounded-xl bg-warning-soft px-3.5 py-2.5 text-sm"
          >
            <.icon name="hero-lock-closed-mini" class="mt-0.5 size-4 shrink-0 text-warning" />
            Summaries are not included in this event's plan.
          </p>

          <p id="summary-announcer" role="status" class="sr-only">
            <span :if={@summary}>Your summary is ready.</span>
          </p>

          <p
            :if={is_nil(@summary) and not @summary_locked}
            id="summary-loading"
            class="flex items-center gap-2 text-sm text-muted"
          >
            <.spinner /> Preparing your summary...
          </p>

          <div :if={@summary} class="space-y-5 motion-safe:animate-enter">
            <p id="cliffnotes" class="whitespace-pre-line text-pretty leading-relaxed">
              {@summary.content["cliffnotes"]}
            </p>

            <div :if={@summary.content["notes"] != []} id="my-notes">
              <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-muted">
                Your notes
              </h3>

              <div class="space-y-2">
                <p
                  :for={n <- @summary.content["notes"]}
                  class="whitespace-pre-line rounded-xl bg-sunken px-3.5 py-2.5 text-pretty"
                >
                  {n}
                </p>
              </div>
            </div>
          </div>
        </.card>

        <div id="attendee-workspace" class="space-y-4 md:space-y-0">
          <div
            id="attendee-tablist"
            phx-hook="TabList"
            role="tablist"
            aria-label="Notes and questions"
            class="grid grid-cols-2 gap-1 rounded-2xl bg-sunken p-1 md:hidden"
          >
            <.tab id="tab-notes" controls="panel-notes" selected phx-click={select_tab("notes")}>
              <.icon name="hero-pencil-square-mini" class="size-4" /> Notes
            </.tab>
            <.tab id="tab-questions" controls="panel-questions" phx-click={select_tab("questions")}>
              <.icon name="hero-chat-bubble-left-right-mini" class="size-4" /> Questions
              <.badge
                :if={MapSet.size(@my_question_ids) > 0}
                id="my-question-count"
                tone="brand"
                aria-label="your questions"
              >
                {MapSet.size(@my_question_ids)}
              </.badge>
            </.tab>
          </div>

          <div class="md:grid md:grid-cols-2 md:items-start md:gap-6">
            <.card
              id="panel-notes"
              role="tabpanel"
              aria-labelledby="tab-notes"
              title="Your notes"
              class="md:block"
            >
              <div :if={is_nil(@user)} class="mb-3">
                <.notice id="notes-unavailable" icon="hero-no-symbol-mini">
                  Notes can't be saved because cookies are off. Turn them on and reload to take notes.
                </.notice>
              </div>

              <.form for={@note_form} id="note-form" phx-change="save_note" phx-submit="save_note">
                <.input
                  field={@note_form[:body]}
                  id="note-body"
                  type="textarea"
                  label="Your notes"
                  aria-describedby="note-help note-status"
                  rows="10"
                  phx-debounce="1000"
                  maxlength={Note.max_length()}
                  disabled={is_nil(@user)}
                  placeholder="Jot down what you want to remember..."
                />
                <div class="mt-2 flex items-center justify-between gap-3 text-xs text-muted">
                  <span id="note-help">Only you can see your notes.</span>
                  <span id="note-status" class="shrink-0" aria-live="polite">
                    <span class="hidden items-center gap-1.5 phx-change-loading:inline-flex">
                      <.spinner class="size-3" /> Saving...
                    </span>
                    <span class="phx-change-loading:hidden">
                      <%= case @note_status do %>
                        <% :saved -> %>
                          <span id="note-saved" class="inline-flex items-center gap-1 text-success">
                            <.icon name="hero-check-mini" class="size-3.5" /> Saved
                          </span>
                        <% :error -> %>
                          <span id="note-not-saved" class="text-danger">Not saved</span>
                        <% :idle -> %>
                          <span>Saves as you type</span>
                      <% end %>
                    </span>
                  </span>
                </div>
              </.form>
            </.card>

            <.card
              id="panel-questions"
              role="tabpanel"
              aria-labelledby="tab-questions"
              title="Questions"
              class="hidden md:block"
            >
              <div class="space-y-4">
                <.notice
                  :if={is_nil(@speech.started_at)}
                  id="questions-not-started"
                  icon="hero-clock-mini"
                >
                  Questions open when the speech starts.
                </.notice>

                <.notice :if={@speech.ended_at} id="questions-closed" icon="hero-lock-closed-mini">
                  The speech has ended, so questions are closed.
                </.notice>

                <.notice
                  :if={questions_open?(@speech) && is_nil(@user)}
                  id="questions-unavailable"
                  icon="hero-no-symbol-mini"
                >
                  Asking needs cookies. Turn them on and reload to ask a question.
                </.notice>

                <.form
                  :if={questions_open?(@speech) && @user}
                  for={@question_form}
                  id="question-form"
                  phx-change="validate_question"
                  phx-submit="submit_question"
                  class="space-y-3"
                >
                  <.input
                    field={@question_form[:text]}
                    id="question-text"
                    type="textarea"
                    rows="3"
                    label="Ask the speaker"
                    maxlength={max_question_length()}
                    placeholder="What would you like to know?"
                    required
                  />
                  <div class="grid grid-cols-[6.5rem_1fr] items-end gap-3">
                    <.input
                      field={@question_form[:slide_number]}
                      id="question-slide"
                      type="number"
                      min="1"
                      inputmode="numeric"
                      label="Slide"
                      placeholder="opt."
                    />
                    <.button id="submit-question" type="submit" phx-disable-with="Sending...">
                      <.icon name="hero-paper-airplane-mini" class="size-4" /> Send
                    </.button>
                  </div>
                </.form>

                <.empty_state
                  :if={MapSet.size(@question_ids) == 0}
                  id="questions-empty"
                  icon="hero-chat-bubble-left-right"
                  title="No questions yet"
                >
                  Questions from the audience will appear here.
                </.empty_state>

                <ul
                  id="questions"
                  phx-update="stream"
                  aria-live="polite"
                  aria-relevant="additions"
                  class="space-y-2"
                >
                  <li
                    :for={{dom_id, item} <- @streams.questions}
                    id={dom_id}
                    class={[
                      "rounded-xl bg-sunken px-3.5 py-3",
                      item.fresh? && "motion-safe:animate-enter"
                    ]}
                  >
                    <p class="whitespace-pre-line break-words text-pretty">{item.question.text}</p>
                    <div class="mt-2 flex flex-wrap items-center gap-2 text-xs text-muted">
                      <.badge :if={@user_id && item.question.user_id == @user_id} tone="brand">
                        You
                      </.badge>
                      <.badge :if={item.question.source == "verbal"} tone="outline">
                        Asked aloud
                      </.badge>
                      <.badge :if={item.question.answered_at} tone="success">Answered</.badge>
                      <.badge tone="outline">
                        {item.question.tag ||
                          Takeaway.Questions.Tagging.label(
                            item.question.slide_number,
                            item.question.offset_ms
                          )}
                      </.badge>
                      <.button
                        :if={
                          @user_id && item.question.user_id == @user_id &&
                            item.question.source == "typed"
                        }
                        id={"retract-question-#{item.id}"}
                        phx-click="retract"
                        phx-value-id={item.id}
                        aria-label="Retract your question"
                        data-confirm="Retract this question?"
                        variant="ghost"
                        class="-my-2 ml-auto text-muted"
                      >
                        <.icon name="hero-arrow-uturn-left-mini" class="size-4" /> Retract
                      </.button>
                    </div>
                  </li>
                </ul>
              </div>
            </.card>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
