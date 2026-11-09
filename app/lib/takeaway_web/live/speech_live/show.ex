defmodule TakeawayWeb.SpeechLive.Show do
  @moduledoc "Speaker's speech page: Start Speech button, join link/code, leaderboard placeholder."
  use TakeawayWeb, :live_view

  alias Takeaway.{Speeches, SpeechCreator}

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
         |> assign(:artifacts, Speeches.list_artifacts(speech.id))}
    end
  end

  @impl true
  def handle_event("start", _params, socket) do
    case SpeechCreator.start_speech(socket.assigns.speech) do
      {:ok, speech} -> {:noreply, assign(socket, :speech, speech)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not start the speech")}
    end
  end

  @impl true
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

        <div :if={@speech.started_at} id="leaderboard-panel" class="card border border-dashed p-4">
          <h2 class="font-semibold">Live question leaderboard</h2>
          <p class="text-sm opacity-70">Questions from attendees will appear here.</p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
