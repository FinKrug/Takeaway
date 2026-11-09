defmodule Takeaway.Questions.Question do
  use Ecto.Schema
  import Ecto.Changeset

  schema "questions" do
    field :text, :string
    field :offset_ms, :integer, default: 0
    field :slide_number, :integer
    field :group_id, :integer
    field :retracted_at, :utc_datetime

    belongs_to :user, Takeaway.Accounts.User
    belongs_to :speech, Takeaway.Speeches.Speech

    timestamps(type: :utc_datetime)
  end

  def changeset(question, attrs) do
    question
    |> cast(attrs, [:text, :offset_ms, :slide_number, :group_id, :user_id, :speech_id])
    |> validate_required([:text, :offset_ms, :user_id, :speech_id])
    |> validate_number(:offset_ms, greater_than_or_equal_to: 0)
    |> validate_number(:slide_number, greater_than: 0)
    |> assoc_constraint(:user)
    |> assoc_constraint(:speech)
  end
end
