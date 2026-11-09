defmodule Takeaway.Accounts do
  @moduledoc "Users: speakers and (possibly anonymous) attendees."
  alias Takeaway.Accounts.User
  alias Takeaway.Repo

  def create_user(attrs), do: %User{} |> User.changeset(attrs) |> Repo.insert()

  def create_speaker(attrs), do: create_user(Map.put(attrs, :role, "speaker"))

  def create_anonymous_attendee,
    do: create_user(%{role: "attendee", anonymous: true})

  def get_user(id), do: Repo.get(User, id)
  def get_user!(id), do: Repo.get!(User, id)
end
