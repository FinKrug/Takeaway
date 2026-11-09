defmodule Takeaway.Notes.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notes" do
    field :body, :string, default: ""

    belongs_to :user, Takeaway.Accounts.User
    belongs_to :speech, Takeaway.Speeches.Speech

    timestamps(type: :utc_datetime)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:body, :user_id, :speech_id])
    |> validate_required([:user_id, :speech_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:speech)
  end
end
