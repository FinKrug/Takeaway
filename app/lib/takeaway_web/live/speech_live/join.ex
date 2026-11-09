defmodule TakeawayWeb.SpeechLive.Join do
  @moduledoc "Minimal attendee landing page for a join link/code (expanded by later cards)."
  use TakeawayWeb, :live_view

  alias Takeaway.{Speeches, SpeechCreator, Summaries}

  @impl true
  def mount(%{"code" => code}, session, socket) do
    case Speeches.get_speech_by_join_code(code) do
      nil ->
        {:ok,
         assign(socket,
           speech: nil,
           page_title: "Join",
           user_id: nil,
           summary: nil,
           summary_locked: false
         )}

      speech ->
        if connected?(socket), do: SpeechCreator.subscribe(speech.id)

        {:ok,
         socket
         |> assign(speech: speech, page_title: speech.title)
         # The signed-in attendee, set in the session by the (separate) sign-in flow.
         |> assign(user_id: session["user_id"], summary: nil, summary_locked: false)
         |> load_summary()}
    end
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
      <div class="mx-auto max-w-xl px-4 py-6 space-y-4">
        <p :if={is_nil(@speech)} id="join-not-found">No speech found for that code.</p>
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
            <p :if={@summary_locked} id="summary-locked" class="text-sm opacity-70">
              Summaries are not included in this event's plan.
            </p>
            <p
              :if={is_nil(@summary) and not @summary_locked}
              id="summary-loading"
              class="text-sm opacity-70"
            >
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
