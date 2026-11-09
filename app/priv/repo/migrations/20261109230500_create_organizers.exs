defmodule Takeaway.Repo.Migrations.CreateOrganizers do
  use Ecto.Migration

  def change do
    create table(:organizers) do
      add :email, :string, null: false
      add :name, :string
      add :password_hash, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizers, [:email])

    alter table(:events) do
      add :organizer_id, references(:organizers, on_delete: :nilify_all)
    end

    create index(:events, [:organizer_id])
  end
end
