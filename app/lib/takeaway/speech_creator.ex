defmodule Takeaway.SpeechCreator do
  @moduledoc """
  Creates a speech together with its uploaded artifacts (plan/transcript and
  slides), and announces speech starts over PubSub.
  """
  alias Takeaway.{Events, Repo, Speeches}

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
  """
  def create_speech(attrs, files \\ []) do
    Repo.transaction(fn ->
      event = default_event()

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

  defp default_event do
    case Events.list_events() do
      [event | _] ->
        event

      [] ->
        {:ok, event} = Events.create_event(%{name: "Open Talks"})
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
