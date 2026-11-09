defmodule Takeaway.Repo.Migrations.AddSpeakerInviteToUsers do
  use Ecto.Migration

  # A passwordless speaker row can only be claimed with a one-time invite token. Only the
  # SHA-256 of the token is stored.
  def change do
    alter table(:users) do
      add :speaker_invite_token_hash, :string
      add :invited_at, :utc_datetime
    end

    create unique_index(:users, [:speaker_invite_token_hash])
  end
end
