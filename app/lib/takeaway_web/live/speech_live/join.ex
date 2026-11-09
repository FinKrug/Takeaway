defmodule TakeawayWeb.SpeechLive.Join do
  @moduledoc "Minimal attendee landing page for a join link/code (expanded by later cards)."
  use TakeawayWeb, :live_view

  alias Takeaway.{Speeches, SpeechCreator, Summaries, Tickets}

  @impl true
  def mount(%{"code" => code} = params, session, socket) do
    case Speeches.get_speech_by_join_code(code) do
      nil ->
        {:ok,
         assign(socket,
           speech: nil,
           page_title: "Join",
           user_id: nil,
           summary: nil,
           summary_locked: false,
           ticket_error: nil
         )}

      speech ->
        case Tickets.validate_for_event(speech.event_id, params["ticket"]) do
          :ok -> mount_attendee(speech, session, socket)
          {:error, reason} -> {:ok, gate(socket, reason)}
        end
    end
  end

  # Ticket missing or invalid: show the gate, never the speech or its updates.
  defp gate(socket, reason),
    do:
      assign(socket,
        speech: nil,
        page_title: "Join",
        user_id: nil,
        summary: nil,
        summary_locked: false,
        ticket_error: reason
      )

  defp mount_attendee(speech, session, socket) do
    if connected?(socket), do: SpeechCreator.subscribe(speech.id)

    {:ok,
     socket
     |> assign(speech: speech, page_title: speech.title, ticket_error: nil)
     # The signed-in attendee, set in the session by the (separate) sign-in flow.
     |> assign(user_id: session["user_id"], summary: nil, summary_locked: false)
     |> load_summary()}
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
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
        <.header>{@speech.title}</.header>
        
        <.card
          :if={is_nil(@speech.started_at)}
          id="join-waiting"
          tone="sunken"
          class="flex items-center gap-3"
        >
          <span class="text-warning"><.live_dot class="size-2.5" /></span>
          <p class="font-medium">Waiting for the speaker to start...</p>
        </.card>
        
        <.card
          :if={@speech.started_at && is_nil(@speech.ended_at)}
          id="join-live"
          tone="brand"
          class="flex items-center gap-3"
        >
          <span class="text-danger"><.live_dot class="size-2.5" /></span>
          <p class="font-medium">The speech is live.</p>
        </.card>
        
        <.card :if={@speech.ended_at} id="join-ended" tone="sunken" class="flex items-center gap-3">
          <.icon name="hero-check-circle" class="size-5 text-success" />
          <p class="font-medium">The speech has ended.</p>
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
      </div>
    </Layouts.app>
    """
  end
end
