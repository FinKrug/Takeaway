defmodule Takeaway.Accounts do
  @moduledoc """
  Users: speakers and attendees (possibly anonymous).

  Everyone with a password can log in. Speakers an organizer adds to a speech by email
  (`ensure_speaker/1`) have no password. They claim that row only with a one-time invite
  token: the organizer creates it (`invite_speaker/1`) and hands the link to the speaker;
  `claim_speaker/2` redeems it. Only the token's SHA-256 is stored, and `register_user/2`
  never claims an existing row. An anonymous attendee who registers keeps their row (and
  so their notes and questions).
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

  Never claims an existing speaker row: an email already in use is a normal unique error.
  Speakers added by an organizer use `claim_speaker/2` with their invite token instead.
  """
  def register_user(attrs, opts \\ []) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    base =
      case attrs["role"] do
        "attendee" -> upgradable(opts[:anonymous_user]) || %User{}
        _ -> %User{}
      end

    base |> User.registration_changeset(attrs) |> Repo.insert_or_update()
  end

  @token_bytes 32

  @doc """
  Creates a one-time invite for a passwordless speaker row and returns the raw token
  (shown once; only its hash is stored). Inviting again replaces the previous token.
  Errors with `:already_registered` when the speaker has a password.
  """
  def invite_speaker(%User{id: id}) when not is_nil(id) do
    token = @token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    {count, _} =
      Repo.update_all(
        from(u in User, where: u.id == ^id and u.role == "speaker" and is_nil(u.password_hash)),
        set: [
          speaker_invite_token_hash: hash_token(token),
          invited_at: DateTime.utc_now(:second)
        ]
      )

    if count == 1, do: {:ok, token}, else: {:error, :already_registered}
  end

  @doc "The passwordless speaker row an invite token belongs to, or `nil`."
  def get_invited_speaker(token) when is_binary(token) and token != "" do
    hash = hash_token(token)

    with %User{role: "speaker", password_hash: nil, speaker_invite_token_hash: stored} = user <-
           Repo.get_by(User, speaker_invite_token_hash: hash),
         true <- Plug.Crypto.secure_compare(stored, hash) do
      user
    else
      _ -> nil
    end
  end

  def get_invited_speaker(_), do: nil

  @doc """
  Claims the speaker row for `token`: sets the name and password (the email stays the
  invited one), clears the token. `{:error, :invalid_token}` for an unknown or used token,
  `{:error, changeset}` when the details are invalid.
  """
  def claim_speaker(token, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    Repo.transaction(fn ->
      with %User{id: id} <- get_invited_speaker(token),
           %User{} = user <- lock_unclaimed(id) do
        attrs = Map.merge(attrs, %{"email" => user.email, "role" => "speaker"})

        changeset =
          user
          |> User.registration_changeset(attrs)
          |> Ecto.Changeset.put_change(:speaker_invite_token_hash, nil)

        case Repo.update(changeset) do
          {:ok, user} -> user
          {:error, changeset} -> Repo.rollback(changeset)
        end
      else
        _ -> Repo.rollback(:invalid_token)
      end
    end)
  end

  defp lock_unclaimed(id) do
    Repo.one(
      from u in User,
        where:
          u.id == ^id and is_nil(u.password_hash) and not is_nil(u.speaker_invite_token_hash),
        lock: "FOR UPDATE"
    )
  end

  defp hash_token(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

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

  @doc "Speeches the speaker gives, with their conference (event) preloaded."
  def list_speeches_for_speaker(%User{id: id}) do
    Repo.all(
      from s in Takeaway.Speeches.Speech,
        where: s.speaker_id == ^id,
        order_by: [desc: s.id],
        preload: :event
    )
  end

  @doc """
  Speeches this user has asked a question in or taken a note in, with their conference
  (event) preloaded.
  """
  def list_speeches_for_attendee(%User{id: id}) do
    asked = from q in Takeaway.Questions.Question, where: q.user_id == ^id, select: q.speech_id
    noted = from n in Takeaway.Notes.Note, where: n.user_id == ^id, select: n.speech_id

    Repo.all(
      from s in Takeaway.Speeches.Speech,
        where: s.id in subquery(asked) or s.id in subquery(noted),
        order_by: [desc: s.id],
        preload: :event
    )
  end

  @doc """
  What the attendee left in each speech: `%{speech_id => %{questions: n, note?: bool}}`.
  Retracted questions and empty notes don't count.
  """
  def attendee_activity(%User{id: id}) do
    questions =
      Repo.all(
        from q in Takeaway.Questions.Question,
          where: q.user_id == ^id and is_nil(q.retracted_at),
          group_by: q.speech_id,
          select: {q.speech_id, count(q.id)}
      )

    notes =
      Repo.all(
        from n in Takeaway.Notes.Note,
          where: n.user_id == ^id and n.body != "",
          select: n.speech_id
      )

    base = Map.new(questions, fn {sid, n} -> {sid, %{questions: n, note?: false}} end)

    Enum.reduce(notes, base, fn sid, acc ->
      Map.update(acc, sid, %{questions: 0, note?: true}, &%{&1 | note?: true})
    end)
  end
end
