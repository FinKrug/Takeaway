defmodule Takeaway.Speeches.Speech do
  use Ecto.Schema
  import Ecto.Changeset

  schema "speeches" do
    field :title, :string
    field :description, :string
    field :tags, {:array, :string}, default: []
    field :join_code, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    # The slide the speaker is on (1-based); nil until they first pick one. Set only via
    # `Takeaway.SpeechCreator.set_current_slide/3`, not through `changeset/2`.
    field :current_slide, :integer

    # The conference the speech is part of, or nil for a standalone talk.
    belongs_to :event, Takeaway.Events.Event
    # The owner; set only through `Takeaway.SpeechCreator.create_speech/3`, never cast.
    belongs_to :organizer, Takeaway.Organizers.Organizer
    belongs_to :speaker, Takeaway.Accounts.User
    has_many :notes, Takeaway.Notes.Note
    has_many :questions, Takeaway.Questions.Question
    has_many :artifacts, Takeaway.Speeches.Artifact

    timestamps(type: :utc_datetime)
  end

  def changeset(speech, attrs) do
    speech
    |> cast(attrs, [
      :title,
      :description,
      :tags,
      :join_code,
      :started_at,
      :ended_at,
      :event_id,
      :speaker_id
    ])
    |> validate_required([:title])
    |> Takeaway.JoinCode.put_join_code()
    |> unique_constraint(:join_code)
    |> assoc_constraint(:event)
    |> assoc_constraint(:speaker)
  end

  @doc """
  Where the speech is in its life: `:live` (started, not ended), `:ended` or `:upcoming`
  (not started yet).
  """
  def status(%__MODULE__{ended_at: %DateTime{}}), do: :ended
  def status(%__MODULE__{started_at: %DateTime{}}), do: :live
  def status(%__MODULE__{}), do: :upcoming
end
