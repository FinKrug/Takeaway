defmodule Takeaway.Repo.Migrations.UniqueNotePerAttendeeAndSpeech do
  use Ecto.Migration

  # The attendee page keeps one note per attendee and speech and autosaves it with an
  # upsert, which needs a unique index. Notes had no UI before, so duplicates are
  # unlikely; if any exist, keep the most recent row of each pair.
  def up do
    execute """
    DELETE FROM notes a
    USING notes b
    WHERE a.speech_id = b.speech_id AND a.user_id = b.user_id AND a.id < b.id
    """

    create unique_index(:notes, [:speech_id, :user_id])
  end

  def down do
    drop index(:notes, [:speech_id, :user_id])
  end
end
