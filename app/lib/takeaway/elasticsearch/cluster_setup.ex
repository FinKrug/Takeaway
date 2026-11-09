defmodule Takeaway.Elasticsearch.ClusterSetup do
  @moduledoc """
  Supervised background worker that initializes Elasticsearch indices
  with their schemas upon application boot if they do not exist yet.
  """

  use GenServer
  require Logger

  alias Takeaway.Elasticsearch

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Run async so startup is never blocked
    send(self(), :setup_indices)
    {:ok, %{retries: 0}}
  end

  @impl true
  def handle_info(:setup_indices, %{retries: retries} = state) do
    case Elasticsearch.init_indices() do
      :ok ->
        Logger.info("[Elasticsearch.ClusterSetup] Indices initialized successfully.")
        {:noreply, state}

      {:error, reason} ->
        if retries < 5 and Application.get_env(:takeaway, :env) != :test do
          Logger.warning(
            "[Elasticsearch.ClusterSetup] ES unreachable (#{inspect(reason)}), retrying in 5s... (attempt #{retries + 1}/5)"
          )

          Process.send_after(self(), :setup_indices, 5_000)
          {:noreply, %{state | retries: retries + 1}}
        else
          Logger.debug(
            "[Elasticsearch.ClusterSetup] Skipping index initialization: #{inspect(reason)}"
          )

          {:noreply, state}
        end
    end
  end
end
