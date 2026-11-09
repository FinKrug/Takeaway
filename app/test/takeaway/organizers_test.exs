defmodule Takeaway.OrganizersTest do
  use Takeaway.DataCase, async: true

  alias Takeaway.{Events, Organizers, SpeechCreator}

  test "register stores a hash, normalizes the email and rejects bad input" do
    {:ok, o} = Organizers.register(%{email: "  Me@Example.COM ", password: "password1"})
    assert o.email == "me@example.com"
    assert String.starts_with?(o.password_hash, "pbkdf2$")
    refute o.password_hash =~ "password1"

    assert {:error, cs} = Organizers.register(%{email: "me@example.com", password: "password1"})
    assert "has already been taken" in errors_on(cs).email

    assert {:error, cs} = Organizers.register(%{email: "nope", password: "short"})
    assert "must be a valid email" in errors_on(cs).email
    assert errors_on(cs).password != []
  end

  test "authenticate checks the password" do
    {:ok, o} = Organizers.register(%{email: "me@example.com", password: "password1"})
    assert Organizers.authenticate("ME@example.com", "password1").id == o.id
    assert Organizers.authenticate("me@example.com", "wrong") == nil
    assert Organizers.authenticate("who@example.com", "password1") == nil
    assert Organizers.authenticate(nil, nil) == nil
  end

  test "a speech belongs to a conference or none, and its organizer owns it" do
    {:ok, a} = Organizers.register(%{email: "a@example.com", password: "password1"})
    {:ok, b} = Organizers.register(%{email: "b@example.com", password: "password1"})

    {:ok, s1} = SpeechCreator.create_speech(%{"title" => "One"}, [], organizer: a)

    {:ok, s2} =
      SpeechCreator.create_speech(%{"title" => "Two"}, [], organizer: a, event: {:new, "Conf"})

    {:ok, s3} =
      SpeechCreator.create_speech(%{"title" => "Three"}, [], organizer: a, event: s2.event_id)

    {:ok, s4} = SpeechCreator.create_speech(%{"title" => "Open"})

    assert s1.event_id == nil
    assert s1.organizer_id == a.id
    assert s2.event_id && s3.event_id == s2.event_id
    assert [%{name: "Conf"}] = Events.list_events_for_organizer(a)
    assert Organizers.owns_speech?(a, s1)
    assert Organizers.owns_speech?(a, s3)
    refute Organizers.owns_speech?(b, s1)
    refute Organizers.owns_speech?(b, s3)
    refute Organizers.owns_speech?(a, s4)

    # Another organizer can't put a speech into a's conference.
    assert {:error, :event_not_found} =
             SpeechCreator.create_speech(%{"title" => "Sneaky"}, [],
               organizer: b,
               event: s2.event_id
             )
  end

  test "the owner of a speech's conference may run it too" do
    {:ok, a} = Organizers.register(%{email: "a@example.com", password: "password1"})
    {:ok, event} = Events.create_event(%{name: "Old"}, a)
    {:ok, speech} = Takeaway.Speeches.create_speech(%{title: "Legacy", event_id: event.id})
    assert speech.organizer_id == nil
    assert Organizers.owns_speech?(a, speech)
  end

  test "Release.claim_unowned_events gives orphans to an organizer" do
    {:ok, o} = Organizers.register(%{email: "me@example.com", password: "password1"})
    {:ok, orphan} = Events.create_event(%{name: "Old"})

    assert {:ok, 1} = Takeaway.Release.claim_unowned_events("me@example.com")
    assert Events.get_event_for_organizer(orphan.id, o)
    assert {:error, :organizer_not_found} = Takeaway.Release.claim_unowned_events("x@example.com")
  end
end
