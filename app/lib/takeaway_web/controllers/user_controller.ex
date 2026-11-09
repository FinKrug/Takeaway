defmodule TakeawayWeb.UserController do
  @moduledoc """
  Speaker and attendee accounts: sign-up, login, logout, the speaker dashboard and the
  attendee account page.

  An attendee who signs up while their session holds an anonymous attendee (from
  `/join/:code`) upgrades that same row, so their notes and questions stay theirs.
  """
  use TakeawayWeb, :controller

  alias Takeaway.Accounts
  alias Takeaway.Accounts.User
  alias TakeawayWeb.UserAuth

  def speaker_dashboard(conn, _params) do
    render(conn, :speaker_dashboard,
      page_title: "Your speeches",
      speeches: Accounts.list_speeches_for_speaker(conn.assigns.current_user)
    )
  end

  def account(conn, _params) do
    render(conn, :account,
      page_title: "Your account",
      speeches: Accounts.list_speeches_for_attendee(conn.assigns.current_user)
    )
  end

  def new_session(conn, _params),
    do:
      render(conn, :log_in,
        page_title: "Log in",
        form: Phoenix.Component.to_form(%{}, as: :user)
      )

  def create_session(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate(email, password) do
      nil ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> render(:log_in,
          page_title: "Log in",
          form: Phoenix.Component.to_form(%{"email" => email}, as: :user)
        )

      user ->
        UserAuth.log_in(conn, user)
    end
  end

  def create_session(conn, _params), do: new_session(conn, %{})

  def new_registration(conn, params) do
    role = if params["role"] == "speaker", do: "speaker", else: "attendee"

    render(conn, :register,
      page_title: "Sign up",
      form: Phoenix.Component.to_form(Accounts.change_registration(%User{role: role}))
    )
  end

  def create_registration(conn, %{"user" => params}) do
    # Only the role, name, email and password are taken from the form.
    attrs = Map.take(params, ~w(role name email password))

    case Accounts.register_user(attrs, anonymous_user: session_user(conn)) do
      {:ok, user} ->
        UserAuth.log_in(conn, user)

      {:error, changeset} ->
        render(conn, :register,
          page_title: "Sign up",
          form: Phoenix.Component.to_form(changeset)
        )
    end
  end

  def create_registration(conn, _params), do: new_registration(conn, %{})

  def delete_session(conn, _params), do: UserAuth.log_out(conn)

  defp session_user(conn) do
    case get_session(conn, :user_id) do
      id when is_integer(id) -> Accounts.get_user(id)
      _ -> nil
    end
  end
end
