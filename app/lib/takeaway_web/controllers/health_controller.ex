defmodule TakeawayWeb.HealthController do
  @moduledoc "Liveness and readiness probes for Kubernetes (deploy/deployment.yaml)."
  use TakeawayWeb, :controller

  def show(conn, _params), do: text(conn, "ok\n")
end
