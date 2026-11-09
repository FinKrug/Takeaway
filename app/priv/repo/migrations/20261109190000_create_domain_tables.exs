defmodule Takeaway.Repo.Migrations.CreateDomainTables do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string
      add :email, :string
      add :role, :string, null: false, default: "attendee"
      add :anonymous, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:events) do
      add :name, :string, null: false
      add :description, :text
      add :tags, {:array, :string}, null: false, default: []
      add :join_code, :string, null: false
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:events, [:join_code])

    create table(:speeches) do
      add :title, :string, null: false
      add :description, :text
      add :tags, {:array, :string}, null: false, default: []
      add :join_code, :string, null: false
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :speaker_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:speeches, [:join_code])
    create index(:speeches, [:event_id])
    create index(:speeches, [:speaker_id])

    create table(:questions) do
      add :text, :text, null: false
      add :offset_ms, :integer, null: false, default: 0
      add :slide_number, :integer
      add :group_id, :integer
      add :retracted_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :speech_id, references(:speeches, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:questions, [:speech_id])
    create index(:questions, [:user_id])
    create index(:questions, [:speech_id, :group_id])

    create table(:notes) do
      add :body, :text, null: false, default: ""
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :speech_id, references(:speeches, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:notes, [:speech_id])
    create index(:notes, [:user_id])

    create table(:artifacts) do
      add :kind, :string, null: false
      add :title, :string
      add :content, :text
      add :url, :string
      add :speech_id, references(:speeches, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:artifacts, [:speech_id])
    create index(:artifacts, [:speech_id, :kind])

    create table(:transcript_segments) do
      add :text, :text, null: false
      add :start_ms, :integer, null: false
      add :end_ms, :integer, null: false
      add :artifact_id, references(:artifacts, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:transcript_segments, [:artifact_id, :start_ms])
  end
end
