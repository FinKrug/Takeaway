defmodule TakeawayWeb.PageStructureTest do
  use TakeawayWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Takeaway.{Accounts, Events, Speeches}

  defp doc(html), do: LazyHTML.from_document(html)
  defp count(doc, sel), do: doc |> LazyHTML.query(sel) |> Enum.count()
  defp title(html), do: doc(html) |> LazyHTML.query("title") |> LazyHTML.text() |> String.trim()

  defp assert_structure(html) do
    d = doc(html)
    assert count(d, "header nav[aria-label]") == 1
    assert count(d, "main#main") == 1
    assert count(d, "h1") == 1
    # skip link is the first focusable element and targets main
    assert count(d, "body a#skip-link[href='#main']") == 1
    first = d |> LazyHTML.query("a, button, input, select, textarea") |> Enum.at(0)
    assert LazyHTML.attribute(first, "id") == ["skip-link"]
    assert html =~ "Skip to content"
  end

  test "home page", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert_structure(html)
    assert title(html) =~ "Takeaway"
  end

  test "organizer pages have unique titles and structure", %{conn: conn} do
    login = conn |> get(~p"/organizers/log_in") |> html_response(200)
    register = conn |> get(~p"/organizers/register") |> html_response(200)
    assert_structure(login)
    assert_structure(register)
    assert title(login) =~ "Organizer log in"
    assert title(register) =~ "Register as an organizer"
    refute title(login) == title(register)
  end

  test "user pages have unique titles and structure", %{conn: conn} do
    login = conn |> get(~p"/users/log_in") |> html_response(200)
    register = conn |> get(~p"/users/register") |> html_response(200)
    assert_structure(login)
    assert_structure(register)
    refute title(login) == title(register)

    speaker = user_fixture(%{role: "speaker", name: "Sam"})
    attendee = user_fixture()
    dashboard = conn |> log_in_user(speaker) |> get(~p"/speaker") |> html_response(200)
    account = conn |> log_in_user(attendee) |> get(~p"/account") |> html_response(200)
    assert_structure(dashboard)
    assert_structure(account)
    assert count(doc(register), "label[for]") >= 4
  end

  test "speaker page titled with the speech title", %{conn: conn} do
    organizer = organizer_fixture()
    {:ok, event} = Events.create_event(%{name: "Conf"}, organizer)
    {:ok, speaker} = Accounts.create_speaker(%{name: "Sam"})

    {:ok, speech} =
      Speeches.create_speech(%{title: "Heading Talk", event_id: event.id, speaker_id: speaker.id})

    conn = log_in_organizer(conn, organizer)
    {:ok, _view, html} = live(conn, ~p"/speeches/#{speech.id}/speak")
    assert title(html) =~ "Heading Talk"
    assert_structure(html)
  end
end
