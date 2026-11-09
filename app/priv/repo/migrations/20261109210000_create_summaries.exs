defmodule Takeaway.Repo.Migrations.CreateSummaries do
  use Ecto.Migration

  def change do
    create table(:summaries) do
      add :kind, :string, null: false
      add :content, :map, null: false, default: %{}
      add :generated_by, :string
      add :speech_id, references(:speeches, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    # One speaker summary per speech, one attendee summary per (speech, user).
    create unique_index(:summaries, [:speech_id],
             where: "kind = 'speaker'",
             name: :summaries_speaker_unique
           )

    create unique_index(:summaries, [:speech_id, :user_id],
             where: "kind = 'attendee'",
             name: :summaries_attendee_unique
           )
  end
end
