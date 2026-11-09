defmodule TakeawayWeb.SpeechLive.Join do
  @moduledoc "Minimal attendee landing page for a join link/code (expanded by later cards)."
  use TakeawayWeb, :live_view

  alias Takeaway.{Speeches, SpeechCreator}

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    case Speeches.get_speech_by_join_code(code) do
      nil ->
        {:ok, assign(socket, speech: nil, page_title: "Join")}

      speech ->
        if connected?(socket), do: SpeechCreator.subscribe(speech.id)
        {:ok, assign(socket, speech: speech, page_title: speech.title)}
    end
  end

  @impl true
  def handle_info({:speech_started, speech}, socket),
    do: {:noreply, assign(socket, :speech, speech)}

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
          <p :if={@speech.started_at} id="join-live">The speech is live.</p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
