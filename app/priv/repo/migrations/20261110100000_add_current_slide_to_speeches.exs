defmodule Takeaway.Repo.Migrations.AddCurrentSlideToSpeeches do
  use Ecto.Migration

  # Nullable, no default: `nil` means the speaker hasn't picked a slide yet. Safe while
  # old pods (which don't know the column) keep serving.
  def change do
    alter table(:speeches) do
      add :current_slide, :integer
    end
  end
end
