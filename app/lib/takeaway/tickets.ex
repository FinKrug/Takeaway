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

  @doc "True when the event has issued any tickets (so attendees must present one)."
  def event_uses_tickets?(event_id),
    do: Repo.exists?(from t in Ticket, where: t.event_id == ^event_id)

  @doc """
  Checks `code` against the event's tickets. Events without tickets always pass.
  Returns `:ok`, `{:error, :ticket_required}` or `{:error, :invalid_ticket}`.
  """
  def validate_for_event(event_id, code) do
    cond do
      not event_uses_tickets?(event_id) -> :ok
      not is_binary(code) or String.trim(code) == "" -> {:error, :ticket_required}
      get_ticket_by_code(event_id, String.trim(code)) -> :ok
      true -> {:error, :invalid_ticket}
    end
  end

  def list_tickets(event_id) do
    Repo.all(from t in Ticket, where: t.event_id == ^event_id, order_by: t.id)
  end

  @max_bulk 500
  @email ~r/^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$/

  @doc """
  Generates `count` unowned tickets for `event` (1..500).
  Returns `{:ok, tickets}` or `{:error, :invalid_count}`.
  """
  def generate_tickets(%Event{} = event, count) when is_integer(count) do
    if count in 1..@max_bulk do
      Repo.transaction(fn ->
        for _ <- 1..count do
          case create_ticket(event) do
            {:ok, t} -> t
            {:error, cs} -> Repo.rollback(cs)
          end
        end
      end)
    else
      {:error, :invalid_count}
    end
  end

  def generate_tickets(_event, _count), do: {:error, :invalid_count}

  @doc """
  Imports tickets from pasted text or CSV: one attendee per line, `email` or
  `email,name` (a header line and blank lines are ignored). Each attendee is found
  or created by email and gets one ticket for `event`; an attendee who already has
  a ticket for the event is skipped.

  Returns `%{created: [ticket], skipped: [email], invalid: [line]}`.
  """
  def import_tickets(%Event{} = event, text) when is_binary(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or header?(&1)))
    |> Enum.take(@max_bulk)
    |> Enum.reduce(%{created: [], skipped: [], invalid: []}, fn line, acc ->
      [email | rest] = line |> String.split(",", parts: 2) |> Enum.map(&String.trim/1)
      email = String.downcase(email)

      if Regex.match?(@email, email) do
        import_one(event, email, List.first(rest), line, acc)
      else
        %{acc | invalid: acc.invalid ++ [line]}
      end
    end)
  end

  defp header?(line), do: line |> String.downcase() |> String.starts_with?("email")

  defp import_one(event, email, name, line, acc) do
    with {:ok, user} <- find_or_create_attendee(email, name),
         nil <- Repo.get_by(Ticket, event_id: event.id, user_id: user.id),
         {:ok, ticket} <- create_ticket(event, user) do
      %{acc | created: acc.created ++ [ticket]}
    else
      %Ticket{} -> %{acc | skipped: acc.skipped ++ [email]}
      _ -> %{acc | invalid: acc.invalid ++ [line]}
    end
  end

  defp find_or_create_attendee(email, name) do
    case Repo.get_by(User, email: email) do
      nil ->
        name = if name in [nil, ""], do: nil, else: name
        Takeaway.Accounts.create_user(%{email: email, name: name, role: "attendee"})

      user ->
        {:ok, user}
    end
  end
end
