defmodule Takeaway.Elasticsearch.ClusterSetup do
  @moduledoc """
  Supervised background worker that initializes Elasticsearch indices
  with their schemas upon application boot if they do not exist yet.
  """

  use GenServer
  require Logger

  alias Takeaway.Elasticsearch

  # Cover a cold Elasticsearch start while keeping initialization bounded.
  @max_retries 29

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    es_config = Application.get_env(:takeaway, :elasticsearch, [])

    auto_setup =
      Keyword.get(es_config, :auto_setup, Application.get_env(:takeaway, :env) != :test)

    if auto_setup do
      # Run async so startup is never blocked
      send(self(), :setup_indices)
    end

    {:ok, %{retries: 0, auto_setup: auto_setup}}
  end

  @impl true
  def handle_info(:setup_indices, %{auto_setup: false} = state) do
    {:noreply, state}
  end

  def handle_info(:setup_indices, %{retries: retries} = state) do
    case Elasticsearch.init_indices() do
      :ok ->
        Logger.info("[Elasticsearch.ClusterSetup] Indices initialized successfully.")
        {:noreply, state}

      {:error, {:mapping_drift, index, fields}} ->
        Logger.error(
          "[Elasticsearch] Mapping drift in #{index}: #{inspect(fields)}; explicitly rebuild the derived index before retrying setup"
        )

        {:noreply, state}

      {:error, reason} ->
        if retries < @max_retries and Application.get_env(:takeaway, :env) != :test do
          Logger.warning(
            "[Elasticsearch.ClusterSetup] ES unreachable (#{inspect(reason)}), retrying in 5s... (retry #{retries + 1}/#{@max_retries})"
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
