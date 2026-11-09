defmodule Takeaway.Accounts.User do
  @moduledoc "A speaker or attendee. Attendees may be anonymous (no name or email)."
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(speaker attendee)

  schema "users" do
    field :name, :string
    field :email, :string
    field :role, :string, default: "attendee"
    field :anonymous, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :role, :anonymous])
    |> validate_inclusion(:role, @roles)
    |> validate_speaker_identified()
    |> unique_constraint(:email)
  end

  # Anonymous attendees are allowed; speakers must have a name.
  defp validate_speaker_identified(changeset) do
    if get_field(changeset, :role) == "speaker" do
      validate_required(changeset, [:name])
    else
      changeset
    end
  end
end
