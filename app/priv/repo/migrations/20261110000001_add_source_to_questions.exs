defmodule Takeaway.Repo.Migrations.AddSourceToQuestions do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :source, :string, null: false, default: "typed"
      add :transcript_segment_id, references(:transcript_segments, on_delete: :nilify_all)
      modify :user_id, :bigint, null: true, from: {:bigint, null: false}
    end

    create unique_index(:questions, [:transcript_segment_id])
  end
end
