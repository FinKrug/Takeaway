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
        {segments, last} = speech.id |> Transcripts.list_segments() |> mark_turns()

        {:ok,
         socket
         |> assign(speech: speech, recording: false, last_speaker: last)
         |> stream(:segments, segments)}
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
    do: {:noreply, insert_segment(socket, seg)}

  @doc false
  def format_ms(ms) do
    s = div(ms, 1000)

    "#{String.pad_leading("#{div(s, 60)}", 2, "0")}:#{String.pad_leading("#{rem(s, 60)}", 2, "0")}"
  end

  @doc """
  Marks the segments that start a new speaker turn (`:new_speaker`), carrying
  on from `last` (the speaker of the segment before them). Returns
  `{segments, last}`; keep `last` in an assign for the next live segment.
  Segments without a speaker never start a turn.
  """
  def mark_turns(segments, last \\ nil) do
    Enum.map_reduce(segments, last, fn seg, prev ->
      speaker = Map.get(seg, :speaker)
      {Map.put(seg, :new_speaker, speaker != nil and speaker != prev), speaker || prev}
    end)
  end

  @doc """
  Stream-inserts one live segment, badging it when the speaker changed.
  Expects a `:last_speaker` assign.
  """
  def insert_segment(socket, seg) do
    {[seg], last} = mark_turns([seg], socket.assigns[:last_speaker])
    socket |> assign(:last_speaker, last) |> stream_insert(:segments, seg)
  end

  @doc """
  A friendly name for a diarization label: our diarizer's `S1` and providers'
  zero-based `SPEAKER_00` both become "Speaker 1"; other labels show as they are.
  """
  def speaker_name(label) do
    case speaker_number(label) do
      nil -> label
      n -> "Speaker #{n}"
    end
  end

  defp speaker_number("SPEAKER_" <> n), do: parse_pos(n, 1)
  defp speaker_number("S" <> n), do: parse_pos(n, 0)
  defp speaker_number(_), do: nil

  defp parse_pos(n, add) do
    case Integer.parse(n) do
      {i, ""} when i + add > 0 -> i + add
      _ -> nil
    end
  end

  @speaker_tones ~w(brand success warning outline)

  @doc false
  def speaker_tone(label) do
    i = (speaker_number(label) || :erlang.phash2(label)) - 1
    Enum.at(@speaker_tones, Integer.mod(i, length(@speaker_tones)))
  end

  attr :id, :string, required: true
  attr :segments, :any, required: true, doc: "the :segments LiveView stream"
  attr :class, :string, default: nil
  slot :empty, doc: "shown only while the stream has no segments"

  @doc """
  Renders transcript segments from a LiveView stream. A segment marked with
  `:new_speaker` (`mark_turns/2`) starts with its speaker's badge.
  """
  def transcript_list(assigns) do
    ~H"""
    <ol id={@id} phx-update="stream" class={["space-y-3", @class]}>
      <li :if={@empty != []} id={"#{@id}-empty"} class="hidden only:block text-sm text-muted">
        {render_slot(@empty)}
      </li>
      <li
        :for={{dom_id, seg} <- @segments}
        id={dom_id}
        data-speaker={seg.speaker}
        class="flex gap-3 leading-relaxed motion-safe:animate-enter"
      >
        <span class="mt-0.5 shrink-0 font-mono text-xs tabular-nums text-muted">
          {format_ms(seg.start_ms)}
        </span>
        <span class="min-w-0 text-pretty">
          <.badge
            :if={Map.get(seg, :new_speaker)}
            tone={speaker_tone(seg.speaker)}
            class="mr-1.5 align-[1px]"
          >
            {speaker_name(seg.speaker)}
          </.badge>
          {seg.text}
        </span>
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
