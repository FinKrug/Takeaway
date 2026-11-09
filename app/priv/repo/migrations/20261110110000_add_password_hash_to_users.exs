defmodule Takeaway.Repo.Migrations.AddPasswordHashToUsers do
  use Ecto.Migration

  # The unique index on users.email already exists (create_domain_tables). Speakers added by
  # an organizer have no password until they register with that email and claim the row.
  def change do
    alter table(:users) do
      add :password_hash, :string
    end
  end
end
