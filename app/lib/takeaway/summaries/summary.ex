defmodule Takeaway.Summaries.Summary do
  @moduledoc """
  A cached post-speech summary. `kind` is "speaker" (one per speech) or
  "attendee" (one per speech and user). `content` is a JSON map, see
  `Takeaway.Summaries`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "summaries" do
    field :kind, :string
    field :content, :map, default: %{}
    field :generated_by, :string

    belongs_to :speech, Takeaway.Speeches.Speech
    belongs_to :user, Takeaway.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [:kind, :content, :generated_by, :speech_id, :user_id])
    |> validate_required([:kind, :content, :speech_id])
    |> validate_inclusion(:kind, ~w(speaker attendee))
    |> unique_constraint(:speech_id, name: :summaries_speaker_unique)
    |> unique_constraint(:speech_id, name: :summaries_attendee_unique)
    |> assoc_constraint(:speech)
  end
end
