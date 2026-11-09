defmodule Takeaway.Speeches.TranscriptSegment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transcript_segments" do
    field :text, :string
    field :start_ms, :integer
    field :end_ms, :integer

    belongs_to :artifact, Takeaway.Speeches.Artifact

    timestamps(type: :utc_datetime)
  end

  def changeset(segment, attrs) do
    segment
    |> cast(attrs, [:text, :start_ms, :end_ms, :artifact_id])
    |> validate_required([:text, :start_ms, :end_ms, :artifact_id])
    |> validate_number(:start_ms, greater_than_or_equal_to: 0)
    |> validate_end_after_start()
    |> assoc_constraint(:artifact)
  end

  defp validate_end_after_start(changeset) do
    start_ms = get_field(changeset, :start_ms)
    end_ms = get_field(changeset, :end_ms)

    if start_ms && end_ms && end_ms < start_ms do
      add_error(changeset, :end_ms, "must not be before start_ms")
    else
      changeset
    end
  end
end
