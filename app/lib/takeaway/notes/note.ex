defmodule Takeaway.Notes.Note do
  use Ecto.Schema
  import Ecto.Changeset

  @max_length 20_000

  schema "notes" do
    field :body, :string, default: ""

    belongs_to :user, Takeaway.Accounts.User
    belongs_to :speech, Takeaway.Speeches.Speech

    timestamps(type: :utc_datetime)
  end

  def max_length, do: @max_length

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:user_id, :speech_id])
    # An emptied note is saved as "" (the column is NOT NULL), not cast to nil.
    |> cast(attrs, [:body], empty_values: [nil])
    |> validate_required([:user_id, :speech_id])
    |> validate_length(:body, max: @max_length)
    |> assoc_constraint(:user)
    |> assoc_constraint(:speech)
    |> unique_constraint([:speech_id, :user_id])
  end
end
