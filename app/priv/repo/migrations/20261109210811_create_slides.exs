defmodule Takeaway.Repo.Migrations.CreateSlides do
  use Ecto.Migration

  # Additive only (new table), so old pods keep working while the migrate init
  # container runs during a rolling deploy.
  def change do
    create table(:slides) do
      add :speech_id, references(:speeches, on_delete: :delete_all), null: false
      add :slide_number, :integer, null: false
      add :text, :text, null: false, default: ""

      timestamps(type: :utc_datetime)
    end

    create unique_index(:slides, [:speech_id, :slide_number])
  end
end
