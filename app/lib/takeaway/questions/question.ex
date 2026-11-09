defmodule Takeaway.Questions.Question do
  use Ecto.Schema
  import Ecto.Changeset

  schema "questions" do
    field :text, :string
    field :offset_ms, :integer, default: 0
    field :slide_number, :integer
    field :context_offset_ms, :integer
    field :tag, :string
    field :context_source, :string
    field :slide_source, :string
    belongs_to :context_segment, Takeaway.Speeches.TranscriptSegment
    field :group_id, :integer
    field :retracted_at, :utc_datetime
    # set when the speaker responds (see `Takeaway.Questions.mark_answered_by_segments/1`)
    field :answered_at, :utc_datetime
    # "typed" (submitted by an attendee) or "verbal" (detected in the audience transcript)
    field :source, :string, default: "typed"

    belongs_to :user, Takeaway.Accounts.User
    belongs_to :speech, Takeaway.Speeches.Speech
    belongs_to :transcript_segment, Takeaway.Speeches.TranscriptSegment

    timestamps(type: :utc_datetime)
  end

  @sources ~w(typed verbal)
  def sources, do: @sources

  def changeset(question, attrs) do
    question
    |> cast(attrs, [
      :text,
      :offset_ms,
      :slide_number,
      :group_id,
      :user_id,
      :speech_id,
      :source,
      :transcript_segment_id
    ])
    |> validate_required([:text, :offset_ms, :speech_id, :source])
    |> validate_inclusion(:source, @sources)
    |> validate_user_for_source()
    |> validate_number(:offset_ms, greater_than_or_equal_to: 0)
    |> validate_number(:slide_number, greater_than: 0)
    |> assoc_constraint(:user)
    |> assoc_constraint(:speech)
    |> unique_constraint(:transcript_segment_id)
  end

  # Typed questions need an asker; verbal ones come from the transcript and have none.
  defp validate_user_for_source(changeset) do
    if get_field(changeset, :source) == "verbal",
      do: changeset,
      else: validate_required(changeset, [:user_id])
  end
end
