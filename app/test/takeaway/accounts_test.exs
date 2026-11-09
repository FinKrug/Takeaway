defmodule Takeaway.AccountsTest do
  use Takeaway.DataCase, async: true

  alias Takeaway.{Accounts, Notes, Questions, Speeches}

  @attrs %{role: "attendee", name: "Ann", email: " Ann@Example.COM ", password: "password1"}

  test "register_user hashes the password and normalizes the email" do
    {:ok, user} = Accounts.register_user(@attrs)
    assert user.email == "ann@example.com"
    assert String.starts_with?(user.password_hash, "pbkdf2$")
    refute user.password_hash =~ "password1"
    refute user.anonymous
  end

  test "register_user validates input and unique emails" do
    assert {:error, cs} =
             Accounts.register_user(%{role: "attendee", email: "nope", password: "x"})

    assert "must be a valid email" in errors_on(cs).email
    assert errors_on(cs).password != []

    assert {:error, cs} = Accounts.register_user(%{@attrs | role: "speaker", name: nil})
    assert "can't be blank" in errors_on(cs).name

    assert {:error, cs} =
             Accounts.register_user(%{@attrs | role: "wizard"})

    assert errors_on(cs).role != []

    {:ok, _} = Accounts.register_user(@attrs)
    assert {:error, cs} = Accounts.register_user(%{@attrs | email: "ann@example.com"})
    assert "has already been taken" in errors_on(cs).email
  end

  test "authenticate checks the password" do
    {:ok, user} = Accounts.register_user(@attrs)
    assert Accounts.authenticate("ANN@example.com", "password1").id == user.id
    assert Accounts.authenticate("ann@example.com", "wrong") == nil
    assert Accounts.authenticate("who@example.com", "password1") == nil
    assert Accounts.authenticate(nil, nil) == nil
    assert Accounts.get_user_by_email(" ANN@example.com ").id == user.id
  end

  test "a user without a password can't log in" do
    {:ok, _} = Accounts.ensure_speaker("sam@example.com")
    assert Accounts.authenticate("sam@example.com", "") == nil
    assert Accounts.authenticate("sam@example.com", "password1") == nil
  end

  test "an anonymous attendee who registers keeps their row, notes and questions" do
    {:ok, anon} = Accounts.create_anonymous_attendee()
    {:ok, speech} = Takeaway.SpeechCreator.create_speech(%{"title" => "Talk"})
    {:ok, _} = Notes.save_note(speech.id, anon.id, "my note")

    {:ok, user} = Accounts.register_user(@attrs, anonymous_user: anon)
    assert user.id == anon.id
    refute user.anonymous
    assert user.email == "ann@example.com"
    assert Accounts.authenticate("ann@example.com", "password1").id == anon.id
    assert [%{id: id}] = Accounts.list_speeches_for_attendee(user)
    assert id == speech.id
  end

  test "an already registered user is never 'upgraded' again" do
    {:ok, first} = Accounts.register_user(@attrs)

    {:ok, other} =
      Accounts.register_user(%{@attrs | email: "other@example.com"}, anonymous_user: first)

    refute other.id == first.id
    assert Accounts.get_user(first.id).email == "ann@example.com"
  end

  test "ensure_speaker creates a passwordless speaker once" do
    assert {:ok, speaker} = Accounts.ensure_speaker(" Sam.Lee@Example.com ")
    assert speaker.role == "speaker"
    assert speaker.name == "sam.lee"
    assert speaker.email == "sam.lee@example.com"
    assert is_nil(speaker.password_hash)
    assert {:ok, same} = Accounts.ensure_speaker("sam.lee@example.com")
    assert same.id == speaker.id
    assert {:error, :invalid_email} = Accounts.ensure_speaker("nope")

    {:ok, _} = Accounts.register_user(@attrs)
    assert {:error, :not_a_speaker} = Accounts.ensure_speaker("ann@example.com")
  end

  test "a speaker registering with a placeholder's email claims that row" do
    {:ok, placeholder} = Accounts.ensure_speaker("sam@example.com")

    {:ok, speech} =
      Takeaway.SpeechCreator.create_speech(%{"title" => "Talk", "speaker_id" => placeholder.id})

    {:ok, user} =
      Accounts.register_user(%{
        role: "speaker",
        name: "Sam Lee",
        email: "SAM@example.com",
        password: "password1"
      })

    assert user.id == placeholder.id
    assert user.name == "Sam Lee"
    assert Accounts.authenticate("sam@example.com", "password1").id == user.id
    assert [%{id: id}] = Accounts.list_speeches_for_speaker(user)
    assert id == speech.id
    assert Accounts.speaks?(user, Speeches.get_speech!(speech.id))

    # Once claimed, the row can't be claimed again.
    assert {:error, cs} =
             Accounts.register_user(%{
               role: "speaker",
               name: "Evil",
               email: "sam@example.com",
               password: "password2"
             })

    assert "has already been taken" in errors_on(cs).email
  end

  test "an attendee sign-up doesn't claim a speaker placeholder" do
    {:ok, _} = Accounts.ensure_speaker("sam@example.com")
    assert {:error, cs} = Accounts.register_user(%{@attrs | email: "sam@example.com"})
    assert "has already been taken" in errors_on(cs).email
  end

  test "speaks? only matches the linked speaker" do
    {:ok, a} =
      Accounts.register_user(%{
        role: "speaker",
        name: "A",
        email: "a@example.com",
        password: "password1"
      })

    {:ok, b} =
      Accounts.register_user(%{
        role: "speaker",
        name: "B",
        email: "b@example.com",
        password: "password1"
      })

    {:ok, att} = Accounts.register_user(@attrs)
    speech = %{speaker_id: a.id}
    assert Accounts.speaks?(a, speech)
    refute Accounts.speaks?(b, speech)
    refute Accounts.speaks?(att, %{speaker_id: att.id})
    refute Accounts.speaks?(nil, speech)
  end

  test "attendee speeches include questions asked" do
    {:ok, user} = Accounts.register_user(@attrs)
    {:ok, speech} = Takeaway.SpeechCreator.create_speech(%{"title" => "Talk"})
    {:ok, _} = Questions.create_question(%{text: "Why?", user_id: user.id, speech_id: speech.id})
    assert [%{id: id}] = Accounts.list_speeches_for_attendee(user)
    assert id == speech.id
  end
end
