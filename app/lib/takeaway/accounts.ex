defmodule Takeaway.Accounts do
  @moduledoc """
  Users: speakers and attendees (possibly anonymous).

  Everyone with a password can log in. Speakers an organizer adds to a speech by email
  (`ensure_speaker/1`) have no password until they register with that email, which claims
  the existing row (`register_user/2`). An anonymous attendee who registers keeps their
  row (and so their notes and questions).
  """
  import Ecto.Query

  alias Takeaway.Accounts.User
  alias Takeaway.Repo

  def create_user(attrs), do: %User{} |> User.changeset(attrs) |> Repo.insert()

  def create_speaker(attrs), do: create_user(Map.put(attrs, :role, "speaker"))

  def create_anonymous_attendee,
    do: create_user(%{role: "attendee", anonymous: true})

  def get_user(id), do: Repo.get(User, id)
  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email),
    do: Repo.get_by(User, email: User.normalize_email(email))

  def get_user_by_email(_), do: nil

  def change_registration(%User{} = user, attrs \\ %{}),
    do: User.registration_changeset(user, attrs)

  @doc """
  Registers a speaker or attendee. Options:

    * `:anonymous_user` - the anonymous attendee of the current session; an attendee
      sign-up upgrades that row instead of inserting a new one.

  A speaker sign-up whose email matches a speaker row without a password claims that row.
  """
  def register_user(attrs, opts \\ []) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    base =
      case attrs["role"] do
        "speaker" -> unclaimed_speaker(User.normalize_email(attrs["email"])) || %User{}
        "attendee" -> upgradable(opts[:anonymous_user]) || %User{}
        _ -> %User{}
      end

    base |> User.registration_changeset(attrs) |> Repo.insert_or_update()
  end

  defp unclaimed_speaker(email) when is_binary(email) do
    case get_user_by_email(email) do
      %User{role: "speaker", password_hash: nil} = user -> user
      _ -> nil
    end
  end

  defp unclaimed_speaker(_), do: nil

  # Re-read the row: only a still-anonymous, passwordless attendee may be upgraded.
  defp upgradable(%User{id: id}) when not is_nil(id) do
    case Repo.get(User, id) do
      %User{anonymous: true, role: "attendee", password_hash: nil} = user -> user
      _ -> nil
    end
  end

  defp upgradable(_), do: nil

  @doc "The user with this email and password, or `nil` (same cost either way)."
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if Takeaway.Passwords.valid?(user && user.password_hash, password), do: user
  end

  def authenticate(_email, _password), do: nil

  @doc """
  The speaker user for `email`, created without a password if there is none yet. Errors
  with `:invalid_email` or `:not_a_speaker` (the email belongs to an attendee account).
  """
  def ensure_speaker(email) do
    email = User.normalize_email(email)

    cond do
      not User.valid_email?(email) ->
        {:error, :invalid_email}

      user = get_user_by_email(email) ->
        if user.role == "speaker", do: {:ok, user}, else: {:error, :not_a_speaker}

      true ->
        create_speaker(%{name: email |> String.split("@") |> hd(), email: email})
    end
  end

  @doc "True when `user` is the speaker the speech was assigned to."
  def speaks?(%User{id: id, role: "speaker"}, %{speaker_id: id}) when not is_nil(id), do: true
  def speaks?(_user, _speech), do: false

  def list_speeches_for_speaker(%User{id: id}) do
    Repo.all(
      from s in Takeaway.Speeches.Speech, where: s.speaker_id == ^id, order_by: [desc: s.id]
    )
  end

  @doc "Speeches this user has asked a question in or taken a note in."
  def list_speeches_for_attendee(%User{id: id}) do
    asked = from q in Takeaway.Questions.Question, where: q.user_id == ^id, select: q.speech_id
    noted = from n in Takeaway.Notes.Note, where: n.user_id == ^id, select: n.speech_id

    Repo.all(
      from s in Takeaway.Speeches.Speech,
        where: s.id in subquery(asked) or s.id in subquery(noted),
        order_by: [desc: s.id]
    )
  end
end
