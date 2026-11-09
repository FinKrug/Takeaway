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
        ticket_error: reason
      )

  defp mount_attendee(speech, session, socket) do
    if connected?(socket), do: SpeechCreator.subscribe(speech.id)

    {:ok,
     socket
     |> assign(speech: speech, page_title: speech.title, ticket_error: nil)
     # The signed-in attendee, set in the session by the (separate) sign-in flow.
     |> assign(user_id: session["user_id"], summary: nil)
     |> load_summary()}
  end

  # After the speech ended, show this attendee's cliffnotes (generated once, cached).
  defp load_summary(%{assigns: %{speech: %{ended_at: %DateTime{}}, user_id: uid}} = socket)
       when not is_nil(uid) do
    speech = socket.assigns.speech

    case Summaries.get_attendee_summary(speech.id, uid) do
      nil ->
        if connected?(socket),
          do: start_async(socket, :summary, fn -> Summaries.attendee_summary(speech, uid) end),
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
      <div class="mx-auto max-w-xl px-4 py-6 space-y-4">
        <p :if={@ticket_error == :ticket_required} id="join-ticket-required">
          A ticket code is required to join this event. Add ?ticket=YOURCODE to the link.
        </p>
        <p :if={@ticket_error == :invalid_ticket} id="join-ticket-invalid">
          That ticket code is not valid for this event.
        </p>
        <p :if={is_nil(@speech) && is_nil(@ticket_error)} id="join-not-found">
          No speech found for that code.
        </p>
        <div :if={@speech} class="space-y-2">
          <.header>{@speech.title}</.header>
          <p :if={is_nil(@speech.started_at)} id="join-waiting">
            Waiting for the speaker to start...
          </p>
          <p :if={@speech.started_at && is_nil(@speech.ended_at)} id="join-live">
            The speech is live.
          </p>
          <p :if={@speech.ended_at} id="join-ended">The speech has ended.</p>
          <div
            :if={@speech.ended_at && @user_id}
            id="attendee-summary"
            class="card bg-base-200 p-4 space-y-3"
          >
            <h2 class="font-semibold text-lg">Your cliffnotes</h2>
            <p :if={is_nil(@summary)} id="summary-loading" class="text-sm opacity-70">
              Preparing your summary...
            </p>
            <div :if={@summary} class="space-y-3">
              <p id="cliffnotes" class="whitespace-pre-line">{@summary.content["cliffnotes"]}</p>
              <div :if={@summary.content["notes"] != []} id="my-notes">
                <h3 class="font-semibold">Your notes</h3>
                <p :for={n <- @summary.content["notes"]} class="whitespace-pre-line">{n}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
