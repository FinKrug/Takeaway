defmodule Takeaway.Repo do
  use Ecto.Repo,
    otp_app: :takeaway,
    adapter: Ecto.Adapters.Postgres
end
