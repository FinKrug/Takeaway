defmodule TakeawayWeb.SpeechLive.New do
  use TakeawayWeb, :live_view

  alias Takeaway.{Accounts, SpeechCreator}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New speech")
     |> assign(
       :form,
       to_form(%{"title" => "", "description" => "", "tags" => "", "speaker_email" => ""},
         as: :speech
       )
     )
     |> allow_upload(:plan,
       accept: ~w(.txt .md .pdf .doc .docx),
       max_entries: 1,
       max_file_size: 10_000_000
     )
     |> allow_upload(:slides,
       accept: ~w(.pdf .ppt .pptx),
       max_entries: 1,
       max_file_size: 50_000_000
     )}
  end

  @impl true
  def handle_event("validate", %{"speech" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :speech))}
  end

  def handle_event("save", %{"speech" => params}, socket) do
    title = String.trim(params["title"] || "")
    speaker_email = String.trim(params["speaker_email"] || "")

    with :ok <- check_title(title),
         {:ok, speaker_id} <- find_speaker(speaker_email) do
      files = consume("plan", :plan, socket) ++ consume("slides", :slides, socket)

      attrs = %{
        "title" => title,
        "description" => params["description"],
        "tags" => params["tags"],
        "speaker_id" => speaker_id
      }

      case SpeechCreator.create_speech(attrs, files, organizer: socket.assigns.current_organizer) do
        {:ok, speech} ->
          {:noreply, push_navigate(socket, to: ~p"/speeches/#{speech.join_code}")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save the speech")}
      end
    else
      {:error, field, message} ->
        {:noreply,
         assign(socket, :form, to_form(params, as: :speech, errors: [{field, {message, []}}]))}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref, "upload" => upload}, socket) do
    name = if upload == "slides", do: :slides, else: :plan
    {:noreply, cancel_upload(socket, name, ref)}
  end

  defp check_title(""), do: {:error, :title, "can't be blank"}
  defp check_title(_), do: :ok

  # An optional speaker email links the speech to that speaker's user (created without a
  # password if new; they claim it when they register with the same email).
  defp find_speaker(""), do: {:ok, nil}

  defp find_speaker(email) do
    case Accounts.ensure_speaker(email) do
      {:ok, user} -> {:ok, user.id}
      {:error, :invalid_email} -> {:error, :speaker_email, "must be a valid email"}
      {:error, :not_a_speaker} -> {:error, :speaker_email, "belongs to an attendee account"}
      {:error, _} -> {:error, :speaker_email, "could not be used"}
    end
  end

  # Copies the temp file out of the upload callback, which deletes it on return.
  defp consume(kind, name, socket) do
    consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
      keep = path <> ".keep"
      File.cp!(path, keep)
      {:ok, {kind, entry.client_name, keep}}
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Create a speech
        <:subtitle>
          Attendees get a code to join. Your plan and slides help Takeaway group their questions
          and write the summary.
        </:subtitle>
      </.header>

      <.form for={@form} id="speech-form" phx-change="validate" phx-submit="save" class="space-y-5">
        <.card class="space-y-4">
          <.input field={@form[:title]} label="Title" placeholder="What's your talk called?" required />
          <.input
            field={@form[:description]}
            type="textarea"
            label="Description"
            placeholder="One or two sentences attendees will see when they join."
            rows="3"
          />
          <.input
            field={@form[:speaker_email]}
            type="email"
            label="Speaker email (optional)"
            placeholder="speaker@example.com"
            hint="Lets this speaker log in and open the speaker page."
          />
          <.input
            field={@form[:tags]}
            label="Tags"
            placeholder="elixir, liveview, realtime"
            hint="Comma separated."
          />
        </.card>

        <.card title="Materials" class="space-y-4">
          <div>
            <label for={@uploads.plan.ref}>
              <.field_label>Speech plan or transcript</.field_label>
            </label>
            <.live_file_input upload={@uploads.plan} class={file_input_class()} />
            <p class="mt-1.5 text-sm text-muted">.txt, .md, .pdf, .doc or .docx, up to 10 MB.</p>
            <.upload_entries upload={@uploads.plan} name="plan" />
          </div>

          <div>
            <label for={@uploads.slides.ref}>
              <.field_label>Slides</.field_label>
            </label>
            <.live_file_input upload={@uploads.slides} class={file_input_class()} />
            <p class="mt-1.5 text-sm text-muted">.pdf, .ppt or .pptx, up to 50 MB.</p>
            <.upload_entries upload={@uploads.slides} name="slides" />
          </div>
        </.card>

        <.button type="submit" size="lg" class="w-full">Create speech</.button>
      </.form>
    </Layouts.app>
    """
  end

  attr :upload, :any, required: true
  attr :name, :string, required: true

  defp upload_entries(assigns) do
    ~H"""
    <div
      :for={entry <- @upload.entries}
      class="mt-2 rounded-xl bg-sunken px-3 py-2 text-sm motion-safe:animate-pop"
    >
      <div class="flex items-center gap-2">
        <.icon name="hero-document-mini" class="size-4 shrink-0 text-muted" />
        <span class="min-w-0 flex-1 truncate font-medium">{entry.client_name}</span>
        <span class="tabular-nums text-muted">{entry.progress}%</span>
        <.button
          type="button"
          variant="ghost"
          size="sm"
          class="-mr-2 h-7 px-2"
          phx-click="cancel-upload"
          phx-value-ref={entry.ref}
          phx-value-upload={@name}
          aria-label={"Remove #{entry.client_name}"}
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </.button>
      </div>
      <div class="mt-2 h-1 overflow-hidden rounded-full bg-line">
        <div
          class="h-full rounded-full bg-brand transition-[width] duration-300"
          style={"width: #{entry.progress}%"}
        />
      </div>
      <p :for={err <- upload_errors(@upload, entry)} class="mt-1.5 font-medium text-danger">
        {error_to_string(err)}
      </p>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "File too large"
  defp error_to_string(:not_accepted), do: "File type not accepted"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(other), do: to_string(other)
end
