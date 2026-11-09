defmodule Takeaway.Speeches.Artifact do
  @moduledoc "A speech plan, slides, additional notes or live transcript."
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(plan slides notes transcript)

  schema "artifacts" do
    field :kind, :string
    field :title, :string
    field :content, :string
    field :url, :string

    belongs_to :speech, Takeaway.Speeches.Speech
    has_many :segments, Takeaway.Speeches.TranscriptSegment

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [:kind, :title, :content, :url, :speech_id])
    |> validate_required([:kind, :speech_id])
    |> validate_inclusion(:kind, @kinds)
    |> assoc_constraint(:speech)
  end
end
