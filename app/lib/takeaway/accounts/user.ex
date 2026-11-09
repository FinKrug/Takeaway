defmodule Takeaway.Accounts.User do
  @moduledoc """
  A speaker or attendee. Attendees may be anonymous (no name or email). A user with a
  `password_hash` can log in; speakers added by an organizer have none until they register.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(speaker attendee)
  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  schema "users" do
    field :name, :string
    field :email, :string
    field :role, :string, default: "attendee"
    field :anonymous, :boolean, default: false
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  def normalize_email(other), do: other

  def valid_email?(email), do: is_binary(email) and Regex.match?(@email, email)

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :role, :anonymous])
    |> update_change(:email, &normalize_email/1)
    |> validate_inclusion(:role, @roles)
    |> validate_speaker_identified()
    |> unique_constraint(:email)
  end

  @doc """
  Sign-up for a speaker or attendee. Requires email and password; speakers also a name.
  Works on a new user, on an anonymous attendee being upgraded, or on a passwordless
  speaker row being claimed (the row ends up non-anonymous with a password).
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :role, :password])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:email, :password])
    |> validate_inclusion(:role, @roles)
    |> validate_speaker_identified()
    |> validate_format(:email, @email, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> validate_length(:password, min: 8, max: 72)
    |> unique_constraint(:email)
    |> put_change(:anonymous, false)
    |> put_hash()
  end

  # Anonymous attendees are allowed; speakers must have a name.
  defp validate_speaker_identified(changeset) do
    if get_field(changeset, :role) == "speaker" do
      validate_required(changeset, [:name])
    else
      changeset
    end
  end

  defp put_hash(%{valid?: true} = changeset) do
    hash = changeset |> get_change(:password) |> Takeaway.Passwords.hash()
    put_change(changeset, :password_hash, hash)
  end

  defp put_hash(changeset), do: changeset
end
