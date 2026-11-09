defmodule Takeaway.Notes do
  @moduledoc "Per-user notes taken during a speech."
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

  def create_note(attrs), do: %Note{} |> Note.changeset(attrs) |> Repo.insert()

  def update_note(%Note{} = note, attrs), do: note |> Note.changeset(attrs) |> Repo.update()
end
