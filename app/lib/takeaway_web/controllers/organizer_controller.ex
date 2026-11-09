defmodule TakeawayWeb.OrganizerController do
  @moduledoc "Organizer sign-up, login, logout and the dashboard with their tickets links."
  use TakeawayWeb, :controller

  alias Takeaway.{Events, Organizers}
  alias Takeaway.Organizers.Organizer
  alias TakeawayWeb.OrganizerAuth

  def dashboard(conn, _params) do
    render(conn, :dashboard,
      events: Events.list_events_for_organizer(conn.assigns.current_organizer)
    )
  end

  def new_session(conn, _params),
    do: render(conn, :log_in, form: Phoenix.Component.to_form(%{}, as: :organizer))

  def create_session(conn, %{"organizer" => %{"email" => email, "password" => password}}) do
    case Organizers.authenticate(email, password) do
      nil ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> render(:log_in, form: Phoenix.Component.to_form(%{"email" => email}, as: :organizer))

      organizer ->
        OrganizerAuth.log_in(conn, organizer)
    end
  end

  def create_session(conn, _params), do: new_session(conn, %{})

  def new_registration(conn, _params),
    do:
      render(conn, :register,
        form: Phoenix.Component.to_form(Organizers.change_registration(%Organizer{}))
      )

  def create_registration(conn, %{"organizer" => params}) do
    case Organizers.register(params) do
      {:ok, organizer} ->
        OrganizerAuth.log_in(conn, organizer)

      {:error, changeset} ->
        render(conn, :register, form: Phoenix.Component.to_form(changeset))
    end
  end

  def create_registration(conn, _params), do: new_registration(conn, %{})

  def delete_session(conn, _params), do: OrganizerAuth.log_out(conn)
end
