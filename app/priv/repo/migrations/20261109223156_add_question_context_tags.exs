defmodule Takeaway.Repo.Migrations.AddQuestionContextTags do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :context_segment_id, references(:transcript_segments, on_delete: :nilify_all)
      add :context_offset_ms, :integer
      add :tag, :string
      add :context_source, :string
      add :slide_source, :string
    end

    create index(:questions, [:speech_id, :context_segment_id])
  end
end
