defmodule Takeaway.Organizers do
  @moduledoc """
  Organizer accounts. Organizers own events; the organizer pages (tickets,
  speech control and speaker pages) are reachable only by an event's owner.

  Passwords are stored as salted PBKDF2-SHA256 hashes (`pbkdf2$iterations$salt$hash`).
  """
  alias Takeaway.Events.Event
  alias Takeaway.Organizers.Organizer
  alias Takeaway.Repo

  def register(attrs),
    do: %Organizer{} |> Organizer.registration_changeset(attrs) |> Repo.insert()

  def change_registration(%Organizer{} = organizer, attrs \\ %{}),
    do: Organizer.registration_changeset(organizer, attrs)

  def get_organizer(id), do: Repo.get(Organizer, id)
  def get_organizer_by_email(email), do: Repo.get_by(Organizer, email: normalize(email))

  @doc "The organizer with this email and password, or `nil` (same cost either way)."
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    organizer = get_organizer_by_email(email)
    if valid_password?(organizer, password), do: organizer
  end

  def authenticate(_email, _password), do: nil

  defp normalize(email), do: email |> String.trim() |> String.downcase()

  @doc "Makes `organizer` the owner of `event`."
  def claim_event(%Event{} = event, %Organizer{} = organizer),
    do: event |> Ecto.Changeset.change(organizer_id: organizer.id) |> Repo.update()

  def owns_event?(%Organizer{id: id}, %Event{organizer_id: id}) when not is_nil(id), do: true
  def owns_event?(_organizer, _event), do: false

  @doc "True when `organizer` owns the event the speech belongs to."
  def owns_speech?(%Organizer{} = organizer, %{event_id: event_id}) do
    case Repo.get(Event, event_id) do
      %Event{} = event -> owns_event?(organizer, event)
      nil -> false
    end
  end

  def owns_speech?(_organizer, _speech), do: false

  def hash_password(password), do: Takeaway.Passwords.hash(password)

  defp valid_password?(%Organizer{password_hash: hash}, password),
    do: Takeaway.Passwords.valid?(hash, password)

  defp valid_password?(nil, password), do: Takeaway.Passwords.valid?(nil, password)
end
