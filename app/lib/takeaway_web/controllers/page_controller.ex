defmodule TakeawayWeb.PageController do
  use TakeawayWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Questions & notes for live talks")
  end

  @doc """
  The landing page's "Join with code" form submits here (GET /join?code=...).
  Normalizes what people type ("abc 234", "abc-234") and sends them to the
  attendee page for that code.
  """
  def join(conn, params) do
    code =
      (params["code"] || "")
      |> String.upcase()
      |> String.replace(~r/[^A-Z0-9]/, "")

    if code == "" do
      conn
      |> put_flash(:error, "Enter the code from the speaker's slide.")
      |> redirect(to: ~p"/#join")
    else
      redirect(conn, to: ~p"/join/#{code}")
    end
  end
end
