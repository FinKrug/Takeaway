defmodule Takeaway.Repo.Migrations.MakeSpeechEventOptional do
  use Ecto.Migration

  # A speech belongs to a conference (event) or to none. Its owner moves from the
  # event onto the speech itself, so a speech without a conference still has one.
  def up do
    alter table(:speeches) do
      add :organizer_id, references(:organizers, on_delete: :nilify_all)

      modify :event_id, references(:events, on_delete: :nilify_all),
        null: true,
        from: {references(:events, on_delete: :delete_all), null: false}
    end

    create index(:speeches, [:organizer_id])

    execute """
    UPDATE speeches AS s SET organizer_id = e.organizer_id
    FROM events AS e WHERE s.event_id = e.id AND e.organizer_id IS NOT NULL
    """
  end

  def down do
    execute "DELETE FROM speeches WHERE event_id IS NULL"

    drop index(:speeches, [:organizer_id])

    alter table(:speeches) do
      remove :organizer_id

      modify :event_id, references(:events, on_delete: :delete_all),
        null: false,
        from: {references(:events, on_delete: :nilify_all), null: true}
    end
  end
end
