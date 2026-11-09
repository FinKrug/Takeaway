defmodule TakeawayWeb.SpeakerLive do
  @moduledoc """
  Speaker page: captures mic audio and shows the live transcript next to the
  audience's questions (stacked on phones, side by side from `lg`).

  Slide controls (Prev/Next, arrow keys, presenter clickers) move the speech's current
  slide while it is live. The slide is saved on the speech and broadcast on the speech
  topic (`Takeaway.SpeechCreator.set_current_slide/3`), so attendees tag their questions
  with it. Only the organizer who owns the speech's event, or the speech's own speaker (logged in as a
  user), can open the page or change the slide; checked on every event.
  """
  use TakeawayWeb, :live_view

  alias Takeaway.{Accounts, Organizers, Questions, Slides, Speeches, SpeechCreator, Transcripts}

  @max_chunk_bytes 8_000_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case runnable_speech(id, socket.assigns) do
      nil ->
        {:ok, socket |> put_flash(:error, "Speech not found") |> redirect(to: ~p"/")}

      speech ->
        if connected?(socket) do
          Transcripts.subscribe(speech.id)
          Questions.subscribe(speech.id)
          # start/end and slide changes (also from the speaker's other tabs or devices)
          SpeechCreator.subscribe(speech.id)
        end

        {segments, last} = speech.id |> Transcripts.list_segments() |> mark_turns()
        slide_count = Slides.count_slides(speech.id)

        # `animate_questions` is false for the initial list (and after a reconnect), so
        # only questions that arrive live get the enter animation.
        {:ok,
         socket
         |> assign(:page_title, speech.title)
         |> assign(
           speech: speech,
           recording: false,
           animate_questions: false,
           last_speaker: last
         )
         |> assign(
           slide_count: slide_count,
           current_slide: SpeechCreator.current_slide(speech, slide_count)
         )
         |> stream(:segments, segments)
         |> stream(:questions, Questions.list_questions(speech.id))}
    end
  end

  # Missing and foreign speeches look the same.
  defp runnable_speech(id, assigns) do
    with {int, ""} <- Integer.parse(to_string(id)),
         %{} = speech <- Speeches.get_speech(int),
         true <- can_run?(assigns, speech) do
      speech
    else
      _ -> nil
    end
  end

  # The event's organizer, or the user the speech was assigned to as speaker.
  defp can_run?(assigns, speech) do
    Organizers.owns_speech?(assigns[:current_organizer], speech) or
      Accounts.speaks?(assigns[:current_user], Speeches.get_speech(speech.id))
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

  def handle_event("next_slide", _params, socket) do
    socket = refresh_slide_count(socket)

    case socket.assigns.current_slide do
      nil -> {:noreply, change_slide(socket, 1)}
      n -> {:noreply, change_slide(socket, n + 1)}
    end
  end

  def handle_event("prev_slide", _params, socket) do
    socket = refresh_slide_count(socket)

    case socket.assigns.current_slide do
      nil -> {:noreply, socket}
      n -> {:noreply, change_slide(socket, n - 1)}
    end
  end

  # Jump to a slide; non-integer or out-of-range values are ignored.
  def handle_event("set_slide", %{"slide" => slide}, socket) do
    socket = refresh_slide_count(socket)
    upper = slide_max(socket.assigns.slide_count)

    case parse_slide(slide) do
      {:ok, n} when n >= 1 and n <= upper -> {:noreply, change_slide(socket, n)}
      _ -> {:noreply, socket}
    end
  end

  defp slide_max(0), do: SpeechCreator.max_slide()
  defp slide_max(count), do: min(count, SpeechCreator.max_slide())

  # Slides are extracted in the background after upload, so a count of 0 read at mount
  # may be out of date: recount before relying on it.
  defp refresh_slide_count(%{assigns: %{slide_count: 0, speech: speech}} = socket) do
    case Slides.count_slides(speech.id) do
      0 ->
        socket

      count ->
        assign(socket,
          slide_count: count,
          current_slide: SpeechCreator.current_slide(speech, count)
        )
    end
  end

  defp refresh_slide_count(socket), do: socket

  defp parse_slide(n) when is_integer(n), do: {:ok, n}

  defp parse_slide(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_slide(_other), do: :error

  # The client is never trusted: the speech must be live and still owned by this organizer.
  defp change_slide(socket, n) do
    %{speech: speech, slide_count: count} = socket.assigns

    cond do
      not slides_open?(speech) ->
        socket

      not can_run?(socket.assigns, speech) ->
        put_flash(socket, :error, "You can't change the slides of this speech")

      true ->
        case SpeechCreator.set_current_slide(speech, n, count) do
          {:ok, moved} ->
            current = SpeechCreator.current_slide(moved, count)
            assign(socket, speech: moved, current_slide: current)

          {:error, _} ->
            put_flash(socket, :error, "Could not change the slide")
        end
    end
  end

  defp slides_open?(%{started_at: %DateTime{}, ended_at: nil}), do: true
  defp slides_open?(_speech), do: false

  defp can_prev?(speech, current),
    do: slides_open?(speech) and is_integer(current) and current > 1

  defp can_next?(speech, current, count),
    do: slides_open?(speech) and (is_nil(current) or current < slide_max(count))

  defp slide_label(nil, _count), do: "No slide yet"
  defp slide_label(n, 0), do: "Slide #{n}"
  defp slide_label(n, count), do: "Slide #{n} of #{count}"

  @impl true
  def handle_info({:transcript_segment, seg}, socket),
    do: {:noreply, insert_segment(socket, seg)}

  # Keep our own `current_slide`: the broadcast struct may carry a stale one.
  def handle_info({event, %{id: id} = speech}, %{assigns: %{speech: %{id: id}}} = socket)
      when event in [:speech_started, :speech_ended] do
    current = %{socket.assigns.speech | started_at: speech.started_at, ended_at: speech.ended_at}
    {:noreply, assign(socket, :speech, current)}
  end

  # From this or another tab of the speaker; the last change wins.
  def handle_info({:slide_changed, id, n}, %{assigns: %{speech: %{id: id}}} = socket)
      when is_integer(n) do
    socket = refresh_slide_count(socket)
    speech = %{socket.assigns.speech | current_slide: n}

    {:noreply,
     assign(socket,
       speech: speech,
       current_slide: SpeechCreator.current_slide(speech, socket.assigns.slide_count)
     )}
  end

  # A repeated event for the same question updates it in place (same DOM id).
  def handle_info({:question_created, q}, socket),
    do: {:noreply, socket |> assign(animate_questions: true) |> stream_insert(:questions, q)}

  # Deleting a question that isn't in the list is a no-op.
  def handle_info({:question_retracted, q}, socket),
    do: {:noreply, stream_delete(socket, :questions, q)}

  def handle_info({:question_tagged, q}, socket) do
    case Questions.get_question(q.id) do
      %{retracted_at: nil} = current -> {:noreply, stream_insert(socket, :questions, current)}
      _ -> {:noreply, socket}
    end
  end

  # Other speech events (e.g. `{:question_answered, q}`) aren't shown here yet.
  def handle_info(_msg, socket), do: {:noreply, socket}

  attr :id, :string, required: true
  attr :question, Takeaway.Questions.Question, required: true
  attr :animate, :boolean, default: false

  defp question_item(assigns) do
    ~H"""
    <li id={@id} class={["rounded-xl bg-sunken p-3", @animate && "motion-safe:animate-enter"]}>
      <p class="text-base font-medium leading-snug text-pretty text-ink sm:text-lg">
        {@question.text}
      </p>
      <div class="mt-2 flex flex-wrap items-center gap-2 text-xs text-muted">
        <.badge tone="outline">
          {@question.tag ||
            Takeaway.Questions.Tagging.label(@question.slide_number, @question.offset_ms)}
        </.badge>
        <.badge :if={@question.source == "verbal"} tone="brand">
          <.icon name="hero-microphone" class="size-3" /> Spoken
        </.badge>
        <.badge :if={@question.source != "verbal"}>
          <.icon name="hero-pencil-square" class="size-3" /> Typed
        </.badge>
      </div>
    </li>
    """
  end

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
    <Layouts.app flash={@flash} wide>
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

      <.card id="slide-controls">
        <div
          id="slide-keys"
          phx-hook=".SlideKeys"
          data-enabled={to_string(slides_open?(@speech))}
          class="flex flex-wrap items-center gap-3"
        >
          <p
            id="slide-position"
            aria-live="polite"
            class="w-full text-center text-xl font-semibold tabular-nums text-ink sm:w-auto sm:flex-1 sm:text-left"
          >
            {slide_label(@current_slide, @slide_count)}
          </p>
          <.button
            id="slide-prev"
            type="button"
            variant="secondary"
            size="lg"
            phx-click="prev_slide"
            disabled={not can_prev?(@speech, @current_slide)}
            aria-label="Previous slide"
            class="flex-1 sm:flex-none"
          >
            <.icon name="hero-chevron-left" class="size-5" /> Prev
          </.button>
          <.button
            id="slide-next"
            type="button"
            size="lg"
            phx-click="next_slide"
            disabled={not can_next?(@speech, @current_slide, @slide_count)}
            aria-label="Next slide"
            class="flex-1 sm:flex-none"
          >
            Next <.icon name="hero-chevron-right" class="size-5" />
          </.button>
        </div>
        <p
          :if={is_nil(@speech.started_at)}
          id="slide-controls-hint"
          class="mt-3 text-sm text-muted"
        >
          Start the speech to change slides.
        </p>
        <p :if={@speech.ended_at} id="slide-controls-hint" class="mt-3 text-sm text-muted">
          The speech has ended.
        </p>
      </.card>

      <div class="grid gap-4 lg:grid-cols-2 lg:items-start">
        <.card title="Live transcript" class="min-w-0">
          <.transcript_list id="transcript" segments={@streams.segments}>
            <:empty>
              The transcript appears here a few seconds after you start the microphone.
            </:empty>
          </.transcript_list>
        </.card>

        <.card id="questions-card" title="Questions" class="min-w-0">
          <ol
            id="questions"
            phx-update="stream"
            aria-live="polite"
            aria-relevant="additions"
            class="space-y-3 lg:max-h-[70vh] lg:overflow-y-auto"
          >
            <li id="questions-empty" class="hidden only:block">
              <.empty_state icon="hero-chat-bubble-left-right" title="No questions yet">
                Questions from the audience appear here as they come in.
              </.empty_state>
            </li>
            <.question_item
              :for={{dom_id, q} <- @streams.questions}
              id={dom_id}
              question={q}
              animate={@animate_questions}
            />
          </ol>
        </.card>
      </div>
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

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SlideKeys">
      // Arrow keys and presenter clickers (PageUp/PageDown) move the slide,
      // unless the speaker is typing somewhere.
      export default {
        mounted() {
          this.onKey = (e) => {
            if (this.el.dataset.enabled !== "true") return
            if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return
            const t = e.target
            if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return
            if (e.key === "ArrowRight" || e.key === "PageDown") {
              e.preventDefault()
              this.pushEvent("next_slide", {})
            } else if (e.key === "ArrowLeft" || e.key === "PageUp") {
              e.preventDefault()
              this.pushEvent("prev_slide", {})
            }
          }
          window.addEventListener("keydown", this.onKey)
        },
        destroyed() { window.removeEventListener("keydown", this.onKey) }
      }
    </script>
    """
  end
end
