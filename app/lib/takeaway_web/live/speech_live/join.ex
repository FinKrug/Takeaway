defmodule TakeawayWeb.SpeechLive.Join do
  @moduledoc "Minimal attendee landing page for a join link/code (expanded by later cards)."
  use TakeawayWeb, :live_view

  alias Takeaway.{Speeches, SpeechCreator, Summaries}

  @impl true
  def mount(%{"code" => code}, session, socket) do
    case Speeches.get_speech_by_join_code(code) do
      nil ->
        {:ok, assign(socket, speech: nil, page_title: "Join", user_id: nil, summary: nil)}

      speech ->
        if connected?(socket), do: SpeechCreator.subscribe(speech.id)

        {:ok,
         socket
         |> assign(speech: speech, page_title: speech.title)
         # The signed-in attendee, set in the session by the (separate) sign-in flow.
         |> assign(user_id: session["user_id"], summary: nil)
         |> load_summary()}
    end
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
      <.empty_state
        :if={is_nil(@speech)}
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
          <p :if={is_nil(@summary)} id="summary-loading" class="flex items-center gap-2 text-sm text-muted">
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
