defmodule TakeawayWeb.OrganizerController do
  @moduledoc "Organizer sign-up, login, logout and the dashboard of their conferences and speeches."
  use TakeawayWeb, :controller

  alias Takeaway.{Events, Organizers, Speeches}
  alias Takeaway.Organizers.Organizer
  alias TakeawayWeb.{OrganizerAuth, SpeechList}

  def dashboard(conn, _params) do
    organizer = conn.assigns.current_organizer
    events = Events.list_events_for_organizer(organizer)
    speeches = Speeches.list_speeches_for_organizer(organizer)

    render(conn, :dashboard,
      page_title: "Your conferences",
      events: events,
      speeches: speeches,
      counts: SpeechList.status_counts(speeches),
      groups: SpeechList.group_by_conference(speeches, events)
    )
  end

  def new_session(conn, _params),
    do:
      render(conn, :log_in,
        page_title: "Organizer log in",
        form: Phoenix.Component.to_form(%{}, as: :organizer)
      )

  def create_session(conn, %{"organizer" => %{"email" => email, "password" => password}}) do
    case Organizers.authenticate(email, password) do
      nil ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> render(:log_in,
          page_title: "Organizer log in",
          form: Phoenix.Component.to_form(%{"email" => email}, as: :organizer)
        )

      organizer ->
        OrganizerAuth.log_in(conn, organizer)
    end
  end

  def create_session(conn, _params), do: new_session(conn, %{})

  def new_registration(conn, _params),
    do:
      render(conn, :register,
        page_title: "Register as an organizer",
        form: Phoenix.Component.to_form(Organizers.change_registration(%Organizer{}))
      )

  def create_registration(conn, %{"organizer" => params}) do
    case Organizers.register(params) do
      {:ok, organizer} ->
        OrganizerAuth.log_in(conn, organizer)

      {:error, changeset} ->
        render(conn, :register,
          page_title: "Register as an organizer",
          form: Phoenix.Component.to_form(changeset)
        )
    end
  end

  def create_registration(conn, _params), do: new_registration(conn, %{})

  def delete_session(conn, _params), do: OrganizerAuth.log_out(conn)
end
