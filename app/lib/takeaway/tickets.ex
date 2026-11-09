defmodule Takeaway.Tickets do
  @moduledoc "Tickets with a unique code per event."
  import Ecto.Query
  alias Takeaway.{JoinCode, Repo}
  alias Takeaway.Tickets.Ticket

  @max_attempts 5

  @doc """
  Creates a ticket. A non-blank `code` is used as given; otherwise an 8-character
  code is generated, retrying with a new one on collision. Each insert runs in a
  savepoint, so a collision inside a surrounding transaction doesn't abort it.
  `opts[:generate]` overrides the code generator (for tests).
  """
  def create_ticket(attrs, opts \\ []) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    case attrs["code"] do
      code when is_binary(code) ->
        if String.trim(code) == "", do: generated(attrs, opts), else: insert(attrs)

      nil ->
        generated(attrs, opts)

      _ ->
        insert(attrs)
    end
  end

  defp generated(attrs, opts) do
    generate = Keyword.get(opts, :generate, fn -> JoinCode.generate(8) end)
    insert_generated(attrs, generate, @max_attempts)
  end

  defp insert_generated(attrs, generate, attempts) do
    result = insert(Map.put(attrs, "code", generate.()))

    if attempts > 1 and code_taken?(result) do
      insert_generated(attrs, generate, attempts - 1)
    else
      result
    end
  end

  defp insert(attrs), do: %Ticket{} |> Ticket.changeset(attrs) |> Repo.insert(mode: :savepoint)

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
