defmodule Takeaway.Organizers.Organizer do
  @moduledoc "An organizer account: owns events and sees their organizer pages."
  use Ecto.Schema
  import Ecto.Changeset

  schema "organizers" do
    field :email, :string
    field :name, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true

    has_many :events, Takeaway.Events.Event

    timestamps(type: :utc_datetime)
  end

  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  def registration_changeset(organizer, attrs) do
    organizer
    |> cast(attrs, [:email, :name, :password])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:email, :password])
    |> validate_format(:email, @email, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> validate_length(:password, min: 8, max: 72)
    |> unique_constraint(:email)
    |> put_hash()
  end

  defp put_hash(%{valid?: true} = changeset) do
    password = get_change(changeset, :password)
    put_change(changeset, :password_hash, Takeaway.Organizers.hash_password(password))
  end

  defp put_hash(changeset), do: changeset
end
