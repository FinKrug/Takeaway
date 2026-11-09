defmodule TakeawayWeb.SpeakerLive do
  @moduledoc "Speaker page: captures mic audio and shows the live transcript."
  use TakeawayWeb, :live_view

  alias Takeaway.{Speeches, Transcripts}

  @max_chunk_bytes 8_000_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case owned_speech(id, socket.assigns.current_organizer) do
      nil ->
        {:ok, socket |> put_flash(:error, "Speech not found") |> redirect(to: ~p"/")}

      speech ->
        if connected?(socket), do: Transcripts.subscribe(speech.id)

        {:ok,
         socket
         |> assign(speech: speech, recording: false)
         |> stream(:segments, Transcripts.list_segments(speech.id))}
    end
  end

  # Missing and foreign speeches look the same.
  defp owned_speech(id, organizer) do
    with {int, ""} <- Integer.parse(to_string(id)),
         %{} = speech <- Speeches.get_speech(int),
         true <- Takeaway.Organizers.owns_speech?(organizer, speech) do
      speech
    else
      _ -> nil
    end
  end

  @impl true
  def handle_event("audio_chunk", %{"data" => b64, "offset_ms" => offset} = params, socket) do
    type = Map.get(params, "content_type", "audio/webm")

    with {:ok, audio} <- Base.decode64(b64),
         true <- byte_size(audio) <= @max_chunk_bytes,
         true <- is_integer(offset) and offset >= 0,
         {:ok, _} <- Transcripts.ingest_chunk(socket.assigns.speech.id, audio, type, offset) do
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not transcribe an audio chunk")}
    end
  end

  def handle_event("recording", %{"on" => on}, socket) when is_boolean(on),
    do: {:noreply, assign(socket, recording: on)}

  @impl true
  def handle_info({:transcript_segment, seg}, socket),
    do: {:noreply, stream_insert(socket, :segments, seg)}

  @doc false
  def format_ms(ms) do
    s = div(ms, 1000)

    "#{String.pad_leading("#{div(s, 60)}", 2, "0")}:#{String.pad_leading("#{rem(s, 60)}", 2, "0")}"
  end

  attr :id, :string, required: true
  attr :segments, :any, required: true, doc: "the :segments LiveView stream"
  attr :class, :string, default: nil
  slot :empty, doc: "shown only while the stream has no segments"

  @doc "Renders transcript segments from a LiveView stream."
  def transcript_list(assigns) do
    ~H"""
    <ol id={@id} phx-update="stream" class={["space-y-3", @class]}>
      <li :if={@empty != []} id={"#{@id}-empty"} class="hidden only:block text-sm text-muted">
        {render_slot(@empty)}
      </li>
      <li
        :for={{dom_id, seg} <- @segments}
        id={dom_id}
        class="flex gap-3 leading-relaxed motion-safe:animate-enter"
      >
        <span class="mt-0.5 shrink-0 font-mono text-xs tabular-nums text-muted">
          {format_ms(seg.start_ms)}
        </span>
        <span class="text-pretty">{seg.text}</span>
      </li>
    </ol>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>{@speech.title}</.header>

      <.card tone={if @recording, do: "brand", else: "default"}>
        <div id="mic" phx-hook=".MicStream" class="flex flex-wrap items-center gap-3">
          <.button
            id="mic-toggle"
            type="button"
            variant={if @recording, do: "danger", else: "primary"}
            size="lg"
            class="flex-1 sm:flex-none"
          >
            <.icon
              name={if @recording, do: "hero-stop-solid", else: "hero-microphone-solid"}
              class="size-5"
            />
            {if @recording, do: "Stop microphone", else: "Start microphone"}
          </.button>
          <.badge :if={@recording} tone="danger"><.live_dot /> Live</.badge>
        </div>
      </.card>

      <.card title="Live transcript">
        <.transcript_list id="transcript" segments={@streams.segments}>
          <:empty>
            The transcript appears here a few seconds after you start the microphone.
          </:empty>
        </.transcript_list>
      </.card>
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".MicStream">
      export default {
        CHUNK_MS: 5000,
        mounted() {
          this.stream = null
          this.recorder = null
          this.startedAt = 0
          this.el.querySelector("#mic-toggle").addEventListener("click", () => {
            this.stream ? this.stop() : this.start()
          })
        },
        destroyed() { this.stop() },
        async start() {
          try {
            this.stream = await navigator.mediaDevices.getUserMedia({audio: true})
          } catch (_e) {
            return
          }
          this.startedAt = Date.now()
          this.pushEvent("recording", {on: true})
          this.cycle()
        },
        // Restart the recorder each interval so every chunk is a standalone,
        // decodable file (timeslice chunks lack container headers).
        cycle() {
          if (!this.stream) return
          const offset = Date.now() - this.startedAt
          const rec = new MediaRecorder(this.stream)
          const parts = []
          rec.ondataavailable = (e) => e.data.size > 0 && parts.push(e.data)
          rec.onstop = async () => {
            if (parts.length === 0) return
            const blob = new Blob(parts, {type: rec.mimeType})
            const buf = new Uint8Array(await blob.arrayBuffer())
            let bin = ""
            for (let i = 0; i < buf.length; i += 0x8000) {
              bin += String.fromCharCode.apply(null, buf.subarray(i, i + 0x8000))
            }
            this.pushEvent("audio_chunk", {
              data: btoa(bin), offset_ms: offset, content_type: rec.mimeType
            })
          }
          rec.start()
          this.recorder = rec
          this.timer = setTimeout(() => { rec.stop(); this.cycle() }, this.CHUNK_MS)
        },
        stop() {
          clearTimeout(this.timer)
          if (this.recorder && this.recorder.state !== "inactive") this.recorder.stop()
          if (this.stream) this.stream.getTracks().forEach((t) => t.stop())
          this.stream = null
          this.recorder = null
          this.pushEvent("recording", {on: false})
        }
      }
    </script>
    """
  end
end
