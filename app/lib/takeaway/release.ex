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
  Prints each event's organizer tickets link, for example:

      bin/takeaway rpc "Takeaway.Release.print_tickets_links()"

  The links contain secret admin tokens: don't paste them anywhere public.
  """
  def print_tickets_links do
    for event <- Takeaway.Events.list_events() do
      IO.puts("#{event.id}\t#{event.name}\t#{Takeaway.Events.tickets_path(event)}")
    end

    :ok
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
