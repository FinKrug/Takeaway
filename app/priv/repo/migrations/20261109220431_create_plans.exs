defmodule Takeaway.Repo.Migrations.CreatePlans do
  use Ecto.Migration

  def change do
    create table(:plans) do
      add :key, :string, null: false
      add :name, :string, null: false
      add :features, {:array, :string}, null: false, default: []
      add :limits, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:plans, [:key])
  end
end
