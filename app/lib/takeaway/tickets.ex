defmodule Takeaway.Tickets do
  @moduledoc "Tickets with a unique code per event."
  import Ecto.Query
  alias Takeaway.Repo
  alias Takeaway.Tickets.Ticket

  @max_attempts 5

  @doc "Creates a ticket; generates a code (retrying on collision) unless one is given."
  def create_ticket(attrs), do: create_ticket(attrs, @max_attempts)

  defp create_ticket(attrs, attempts) do
    given? = Map.has_key?(attrs, :code) or Map.has_key?(attrs, "code")
    result = %Ticket{} |> Ticket.changeset(attrs) |> Repo.insert()

    if not given? and attempts > 1 and code_taken?(result) do
      create_ticket(attrs, attempts - 1)
    else
      result
    end
  end

  defp code_taken?({:error, %Ecto.Changeset{errors: errors}}) do
    match?({_, opts} when is_list(opts), errors[:code]) and
      Keyword.get(elem(errors[:code], 1), :constraint) == :unique
  end

  defp code_taken?(_), do: false

  def get_ticket_by_code(event_id, code) when is_binary(code) do
    Repo.one(from t in Ticket, where: t.event_id == ^event_id and t.code == ^String.upcase(code))
  end

  def list_tickets(event_id) do
    Repo.all(from t in Ticket, where: t.event_id == ^event_id, order_by: t.id)
  end
end
