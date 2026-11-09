defmodule Takeaway.Release do
  @moduledoc """
  Tasks run from the release, where Mix isn't available.
  The Deployment's init container runs `bin/migrate` before the app starts.
  """
  @app :takeaway

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Gives every event that has no owner to the organizer registered with `email`,
  so events created before organizer accounts stay reachable. Example:

      bin/takeaway rpc 'Takeaway.Release.claim_unowned_events("me@example.com")'

  Returns `{:ok, count}` or `{:error, :organizer_not_found}`.
  """
  def claim_unowned_events(email) do
    load_app()

    case Takeaway.Organizers.get_organizer_by_email(email) do
      nil ->
        {:error, :organizer_not_found}

      organizer ->
        events = Enum.filter(Takeaway.Events.list_events(), &is_nil(&1.organizer_id))
        Enum.each(events, &Takeaway.Organizers.claim_event(&1, organizer))
        {:ok, length(events)}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
