defmodule Takeaway.Notes do
  @moduledoc "Per-user notes taken during a speech. The attendee page keeps one note per user and speech."
  import Ecto.Query
  alias Takeaway.Notes.Note
  alias Takeaway.Repo

  def list_notes(speech_id, user_id) do
    Repo.all(
      from n in Note,
        where: n.speech_id == ^speech_id and n.user_id == ^user_id,
        order_by: [asc: n.id]
    )
  end

  def get_note(id), do: Repo.get(Note, id)
  def get_note!(id), do: Repo.get!(Note, id)

  @doc "The user's note for a speech, or nil."
  def get_note_for(speech_id, user_id),
    do: Repo.get_by(Note, speech_id: speech_id, user_id: user_id)

  def create_note(attrs), do: %Note{} |> Note.changeset(attrs) |> Repo.insert()

  def update_note(%Note{} = note, attrs), do: note |> Note.changeset(attrs) |> Repo.update()

  @doc """
  Saves `body` as the user's note for a speech: inserts the note or overwrites its body
  (last write wins), so there is only ever one row per user and speech.
  Returns `{:ok, note}` or `{:error, changeset}` (for example when the body is too long).
  """
  def save_note(speech_id, user_id, body) do
    %Note{}
    |> Note.changeset(%{body: body || "", speech_id: speech_id, user_id: user_id})
    |> Repo.insert(
      on_conflict: {:replace, [:body, :updated_at]},
      conflict_target: [:speech_id, :user_id],
      returning: true
    )
  end
end
