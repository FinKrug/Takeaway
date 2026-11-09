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

  test "speeches created by an organizer land in their own event" do
    {:ok, a} = Organizers.register(%{email: "a@example.com", password: "password1"})
    {:ok, b} = Organizers.register(%{email: "b@example.com", password: "password1"})

    {:ok, s1} = SpeechCreator.create_speech(%{"title" => "One"}, [], organizer: a)
    {:ok, s2} = SpeechCreator.create_speech(%{"title" => "Two"}, [], organizer: a)
    {:ok, s3} = SpeechCreator.create_speech(%{"title" => "Three"}, [], organizer: b)
    {:ok, s4} = SpeechCreator.create_speech(%{"title" => "Open"})

    assert s1.event_id == s2.event_id
    assert s3.event_id != s1.event_id
    assert Organizers.owns_speech?(a, s1)
    refute Organizers.owns_speech?(b, s1)
    refute Organizers.owns_speech?(a, s4)
    assert [_] = Events.list_events_for_organizer(a)
  end

  test "Release.claim_unowned_events gives orphans to an organizer" do
    {:ok, o} = Organizers.register(%{email: "me@example.com", password: "password1"})
    {:ok, orphan} = Events.create_event(%{name: "Old"})

    assert {:ok, 1} = Takeaway.Release.claim_unowned_events("me@example.com")
    assert Events.get_event_for_organizer(orphan.id, o)
    assert {:error, :organizer_not_found} = Takeaway.Release.claim_unowned_events("x@example.com")
  end
end
