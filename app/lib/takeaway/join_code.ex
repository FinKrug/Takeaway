defmodule Takeaway.JoinCode do
  @moduledoc false
  import Ecto.Changeset

  # No 0/O/1/I to keep codes readable.
  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  def generate(length \\ 6) do
    for _ <- 1..length, into: "", do: <<Enum.random(@alphabet)>>
  end

  def put_join_code(changeset), do: put_code(changeset, :join_code, 6)

  def put_code(changeset, field, length) do
    if get_field(changeset, field) do
      changeset
    else
      put_change(changeset, field, generate(length))
    end
  end
end
