defmodule Takeaway.Repo.Migrations.CreateQuestionGroups do
  use Ecto.Migration

  def change do
    create table(:question_groups) do
      add :speech_id, references(:speeches, on_delete: :delete_all), null: false
      add :text, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:question_groups, [:speech_id])
  end
end
