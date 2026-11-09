defmodule Takeaway.Repo.Migrations.AddAdminTokenToEvents do
  use Ecto.Migration

  def up do
    alter table(:events) do
      add :admin_token, :string
    end

    # Backfill existing events with a random 32-hex-char token.
    execute "UPDATE events SET admin_token = replace(gen_random_uuid()::text, '-', '') WHERE admin_token IS NULL"

    alter table(:events) do
      modify :admin_token, :string,
        null: false,
        default: fragment("replace(gen_random_uuid()::text, '-', '')")
    end

    create unique_index(:events, [:admin_token])
  end

  def down do
    alter table(:events) do
      remove :admin_token
    end
  end
end
