defmodule TakeawayWeb.SpeechLive.New do
  use TakeawayWeb, :live_view

  alias Takeaway.SpeechCreator

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New speech")
     |> assign(:form, to_form(%{"title" => "", "description" => "", "tags" => ""}, as: :speech))
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

    if title == "" do
      {:noreply,
       assign(
         socket,
         :form,
         to_form(params, as: :speech, errors: [title: {"can't be blank", []}])
       )}
    else
      files = consume("plan", :plan, socket) ++ consume("slides", :slides, socket)

      attrs = %{
        "title" => title,
        "description" => params["description"],
        "tags" => params["tags"]
      }

      case SpeechCreator.create_speech(attrs, files, organizer: socket.assigns.current_organizer) do
        {:ok, speech} ->
          {:noreply, push_navigate(socket, to: ~p"/speeches/#{speech.join_code}")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save the speech")}
      end
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref, "upload" => upload}, socket) do
    name = if upload == "slides", do: :slides, else: :plan
    {:noreply, cancel_upload(socket, name, ref)}
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
      <div class="mx-auto max-w-xl px-4 py-6 space-y-6">
        <.header>Create a speech</.header>
        <.form for={@form} id="speech-form" phx-change="validate" phx-submit="save" class="space-y-4">
          <.input field={@form[:title]} label="Title" required />
          <.input field={@form[:description]} type="textarea" label="Description" />
          <.input
            field={@form[:tags]}
            label="Tags (comma separated)"
            placeholder="elixir, liveview, realtime"
          />

          <div>
            <label class="label font-semibold mb-1">Speech plan / transcript</label>
            <.live_file_input upload={@uploads.plan} class="file-input w-full" />
            <.upload_entries upload={@uploads.plan} name="plan" />
          </div>

          <div>
            <label class="label font-semibold mb-1">Slides</label>
            <.live_file_input upload={@uploads.slides} class="file-input w-full" />
            <.upload_entries upload={@uploads.slides} name="slides" />
          </div>

          <button type="submit" class="btn btn-primary w-full">Create speech</button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  attr :upload, :any, required: true
  attr :name, :string, required: true

  defp upload_entries(assigns) do
    ~H"""
    <div :for={entry <- @upload.entries} class="flex items-center gap-2 text-sm mt-1">
      <span class="flex-1 truncate">{entry.client_name} ({entry.progress}%)</span>
      <button
        type="button"
        phx-click="cancel-upload"
        phx-value-ref={entry.ref}
        phx-value-upload={@name}
        class="btn btn-ghost btn-xs"
      >
        remove
      </button>
      <span :for={err <- upload_errors(@upload, entry)} class="text-error">
        {error_to_string(err)}
      </span>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "File too large"
  defp error_to_string(:not_accepted), do: "File type not accepted"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(other), do: to_string(other)
end
