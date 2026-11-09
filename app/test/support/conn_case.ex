defmodule TakeawayWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use TakeawayWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint TakeawayWeb.Endpoint

      use TakeawayWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import TakeawayWeb.ConnCase
    end
  end

  @doc "Registers an organizer with a unique email."
  def organizer_fixture(attrs \\ %{}) do
    {:ok, organizer} =
      attrs
      |> Enum.into(%{
        email: "org#{System.unique_integer([:positive])}@example.com",
        password: "correct horse"
      })
      |> Takeaway.Organizers.register()

    organizer
  end

  @doc "Puts the organizer's login in the test session."
  def log_in_organizer(conn, organizer),
    do: Phoenix.ConnTest.init_test_session(conn, %{"organizer_id" => organizer.id})

  setup tags do
    Takeaway.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
