defmodule Takeaway.SpeechCreator do
  @moduledoc """
  Creates a speech together with its uploaded artifacts (plan/transcript and
  slides), and announces speech starts over PubSub.
  """
  alias Takeaway.{Events, Repo, Slides, Speeches}

  @topic_prefix "speech:"
  @text_exts ~w(.txt .md)

  def topic(speech_id), do: @topic_prefix <> to_string(speech_id)

  def subscribe(speech_id), do: Phoenix.PubSub.subscribe(Takeaway.PubSub, topic(speech_id))

  @doc "Directory where uploaded files are stored."
  def uploads_dir do
    Application.get_env(:takeaway, :uploads_dir) ||
      Path.join(System.tmp_dir!(), "takeaway_uploads")
  end

  @doc "Parses 'a, b ,c' into a unique, trimmed, lowercase tag list."
  def parse_tags(nil), do: []

  def parse_tags(str) when is_binary(str) do
    str
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @doc """
  `files` is a list of `{kind, client_name, source_path}` where kind is
  "plan" or "slides". Copies each file into the uploads dir and saves an
  artifact. Everything happens in one transaction.

  With `opts[:organizer]` the speech joins that organizer's event (created on
  first use), so only they can run it. Without one it joins a shared, unowned event.

  After the transaction commits, the text of each slides artifact is extracted
  in the background (`Takeaway.Slides.extract_async/1`); this function doesn't
  wait for it.
  """
  def create_speech(attrs, files \\ [], opts \\ []) do
    with {:ok, speech} <- insert_speech(attrs, files, opts) do
      speech.id
      |> Speeches.list_artifacts("slides")
      |> Enum.each(&Slides.extract_async/1)

      {:ok, speech}
    end
  end

  defp insert_speech(attrs, files, opts) do
    Repo.transaction(fn ->
      event = event_for(opts[:organizer])

      speech_attrs =
        attrs
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.put("event_id", event.id)
        |> Map.update("tags", [], fn
          t when is_binary(t) -> parse_tags(t)
          t -> t
        end)

      with {:ok, speech} <- Speeches.create_speech(speech_attrs),
           :ok <- save_files(speech, files) do
        speech
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp save_files(speech, files) do
    Enum.reduce_while(files, :ok, fn {kind, name, path}, :ok ->
      case save_file(speech, kind, name, path) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp save_file(speech, kind, name, path) do
    ext = name |> Path.extname() |> String.downcase()
    stored = "#{speech.id}-#{kind}-#{System.unique_integer([:positive])}#{ext}"
    dir = uploads_dir()
    File.mkdir_p!(dir)
    File.cp!(path, Path.join(dir, stored))

    content =
      if kind == "plan" and ext in @text_exts do
        case File.read(path) do
          {:ok, text} -> if String.valid?(text), do: text
          _ -> nil
        end
      end

    Speeches.create_artifact(%{
      speech_id: speech.id,
      kind: kind,
      title: name,
      content: content,
      url: stored
    })
  end

  defp event_for(nil) do
    case Enum.find(Events.list_events(), &is_nil(&1.organizer_id)) do
      nil ->
        {:ok, event} = Events.create_event(%{name: "Open Talks"})
        event

      event ->
        event
    end
  end

  defp event_for(organizer) do
    case Events.list_events_for_organizer(organizer) do
      [] ->
        {:ok, event} = Events.create_event(%{name: "Open Talks"}, organizer)
        event

      [event | _] ->
        event
    end
  end

  @doc "Starts the speech (sets started_at) and broadcasts `{:speech_started, speech}`."
  def start_speech(speech) do
    with {:ok, started} <- Speeches.start_speech(speech) do
      Phoenix.PubSub.broadcast(Takeaway.PubSub, topic(speech.id), {:speech_started, started})
      {:ok, started}
    end
  end

  @doc """
  Ends the speech (sets ended_at) and broadcasts `{:speech_ended, speech}`.
  Idempotent: an already-ended speech is returned unchanged and not re-announced.
  """
  def end_speech(%{ended_at: %DateTime{}} = speech), do: {:ok, speech}

  def end_speech(speech) do
    with {:ok, ended} <- Speeches.end_speech(speech) do
      Phoenix.PubSub.broadcast(Takeaway.PubSub, topic(speech.id), {:speech_ended, ended})
      {:ok, ended}
    end
  end
end
