defmodule Takeaway.Tickets do
  @moduledoc "Tickets with a unique code per event."
  import Ecto.Query
  alias Takeaway.{JoinCode, Repo}
  alias Takeaway.Accounts.User
  alias Takeaway.Events.Event
  alias Takeaway.Tickets.Ticket

  @max_attempts 5

  @doc """
  Creates a ticket for `event`, owned by `user` (or nobody when `nil`).

  Ownership comes only from the `event` and `user` structs, never from `attrs`:
  only `code` is read from `attrs`, so request params can't pick the event or owner.
  A non-blank `code` is used as given; otherwise an 8-character code is generated,
  retrying with a new one on collision. Each insert runs in a savepoint, so a
  collision inside a surrounding transaction doesn't abort it.
  `opts[:generate]` overrides the code generator (for tests).
  """
  def create_ticket(%Event{} = event, user \\ nil, attrs \\ %{}, opts \\ [])
      when is_nil(user) or is_struct(user, User) do
    ticket = %Ticket{event_id: event.id, user_id: user && user.id}
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    case attrs["code"] do
      code when is_binary(code) ->
        if String.trim(code) == "",
          do: generated(ticket, attrs, opts),
          else: insert(ticket, attrs)

      nil ->
        generated(ticket, attrs, opts)

      _ ->
        insert(ticket, attrs)
    end
  end

  defp generated(ticket, attrs, opts) do
    generate = Keyword.get(opts, :generate, fn -> JoinCode.generate(8) end)
    insert_generated(ticket, attrs, generate, @max_attempts)
  end

  defp insert_generated(ticket, attrs, generate, attempts) do
    result = insert(ticket, Map.put(attrs, "code", generate.()))

    if attempts > 1 and code_taken?(result) do
      insert_generated(ticket, attrs, generate, attempts - 1)
    else
      result
    end
  end

  defp insert(ticket, attrs),
    do: ticket |> Ticket.changeset(attrs) |> Repo.insert(mode: :savepoint)

  defp code_taken?({:error, %Ecto.Changeset{errors: errors}}) do
    case errors[:code] do
      {_, opts} -> opts[:constraint] == :unique
      _ -> false
    end
  end

  defp code_taken?(_), do: false

  def get_ticket_by_code(event_id, code) when is_binary(code) do
    Repo.one(from t in Ticket, where: t.event_id == ^event_id and t.code == ^String.upcase(code))
  end

  def list_tickets(event_id) do
    Repo.all(from t in Ticket, where: t.event_id == ^event_id, order_by: t.id)
  end
end
