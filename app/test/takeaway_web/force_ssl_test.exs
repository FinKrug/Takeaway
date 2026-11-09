defmodule TakeawayWeb.ForceSslTest do
  use ExUnit.Case, async: true
  import Plug.Test

  # Mirrors the force_ssl options in config/prod.exs (compile-time there, so
  # the prod config file is read here to keep the test honest).
  defp opts do
    {:ok, config} = Config.Reader.read!("config/prod.exs") |> Keyword.fetch(:takeaway)
    ssl = config |> Keyword.fetch!(TakeawayWeb.Endpoint) |> Keyword.fetch!(:force_ssl)
    Plug.SSL.init(ssl)
  end

  test "probe paths are not redirected over plain HTTP" do
    for path <- ["/healthz", "/readyz"] do
      conn = conn(:get, path) |> Plug.SSL.call(opts())
      refute conn.halted
      assert conn.status != 301
    end
  end

  test "other paths over plain HTTP are redirected" do
    conn = conn(:get, "/") |> Plug.SSL.call(opts())
    assert conn.status == 301
  end
end
