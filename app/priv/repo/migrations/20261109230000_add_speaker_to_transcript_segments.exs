defmodule Takeaway.Repo.Migrations.AddSpeakerToTranscriptSegments do
  use Ecto.Migration

  def change do
    alter table(:transcript_segments) do
      add :speaker, :string
    end
  end
end
