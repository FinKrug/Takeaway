defmodule Takeaway.JoinCode do
  @moduledoc false
  import Ecto.Changeset

  # No 0/O/1/I to keep codes readable.
  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  def generate(length \\ 6) do
    for _ <- 1..length, into: "", do: <<Enum.random(@alphabet)>>
  end

  def put_join_code(changeset) do
    if get_field(changeset, :join_code) do
      changeset
    else
      put_change(changeset, :join_code, generate())
    end
  end
end
