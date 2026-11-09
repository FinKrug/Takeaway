defmodule TakeawayWeb.PageControllerTest do
  use TakeawayWeb.ConnCase

  describe "GET /" do
    test "shows the join-with-code form and the create-a-speech link", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)
      doc = LazyHTML.from_document(html)

      assert has?(doc, "form#join-form[action='/join'][method='get'] input[name='code']")
      assert has?(doc, "a#create-speech-link[href='/speeches/new']")
      assert has?(doc, "header nav a#nav-new-speech[href='/speeches/new']")
      assert has?(doc, "main#main")
    end
  end

  describe "GET /join" do
    test "normalizes the typed code and sends attendees to the speech", %{conn: conn} do
      conn = get(conn, ~p"/join", code: " abc-234 ")
      assert redirected_to(conn) == ~p"/join/ABC234"
    end

    test "asks for a code when none is given", %{conn: conn} do
      conn = get(conn, ~p"/join", code: "  ")
      assert redirected_to(conn) == "/#join"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Enter the code"
    end
  end

  defp has?(doc, selector), do: LazyHTML.query(doc, selector) |> Enum.count() > 0
end
