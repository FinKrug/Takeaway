defmodule Takeaway.Passwords do
  @moduledoc """
  Password hashing shared by every account type (organizers, speakers, attendees).

  Passwords are stored as salted PBKDF2-SHA256 hashes (`pbkdf2$iterations$salt$hash`).
  """

  @default_iterations 210_000

  def hash(password) do
    salt = :crypto.strong_rand_bytes(16)
    iterations = iterations()
    hash = derive(password, salt, iterations)
    "pbkdf2$#{iterations}$#{Base.encode64(salt)}$#{Base.encode64(hash)}"
  end

  @doc """
  True when `password` matches `stored_hash`. A missing account or one without a password
  (anything but a binary hash) costs the same time as a real check, so unknown emails
  can't be told apart from wrong passwords.
  """
  def valid?(stored_hash, password) when is_binary(stored_hash) do
    with ["pbkdf2", iterations, salt, expected] <- String.split(stored_hash, "$"),
         {iterations, ""} <- Integer.parse(iterations),
         {:ok, salt} <- Base.decode64(salt),
         {:ok, expected} <- Base.decode64(expected) do
      Plug.Crypto.secure_compare(derive(password, salt, iterations), expected)
    else
      _ -> false
    end
  end

  def valid?(_no_hash, password) do
    _ = hash(password)
    false
  end

  defp derive(password, salt, iterations),
    do: :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, 32)

  defp iterations, do: Application.get_env(:takeaway, :pbkdf2_iterations, @default_iterations)
end
