defmodule Takeaway.Repo.Migrations.AddAnsweredAtToQuestions do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :answered_at, :utc_datetime
    end
  end
end
