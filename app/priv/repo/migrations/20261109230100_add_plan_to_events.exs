defmodule Takeaway.Repo.Migrations.AddPlanToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :plan_id, references(:plans, on_delete: :nilify_all)
    end

    create index(:events, [:plan_id])
  end
end
