defmodule Takeaway.DomainTest do
  use Takeaway.DataCase, async: true

  alias Takeaway.{Accounts, Events, Notes, Questions, Speeches}

  setup do
    {:ok, event} = Events.create_event(%{name: "Conf", tags: ["a", "b"]})
    {:ok, speaker} = Accounts.create_speaker(%{name: "Sam"})

    {:ok, speech} =
      Speeches.create_speech(%{title: "Talk", event_id: event.id, speaker_id: speaker.id})

    {:ok, attendee} = Accounts.create_anonymous_attendee()
    %{event: event, speaker: speaker, speech: speech, attendee: attendee}
  end

  describe "users" do
    test "anonymous attendee is allowed, nameless speaker is not", %{attendee: a} do
      assert a.anonymous and is_nil(a.name) and a.role == "attendee"
      assert {:error, cs} = Accounts.create_speaker(%{})
      assert "can't be blank" in errors_on(cs).name
      assert {:error, cs} = Accounts.create_user(%{role: "admin"})
      assert "is invalid" in errors_on(cs).role
    end
  end

  describe "events" do
    test "create generates join code, list and get", %{event: event} do
      assert String.length(event.join_code) == 6
      assert event.tags == ["a", "b"]
      assert Events.get_event!(event.id).id == event.id
      assert Events.get_event_by_join_code(String.downcase(event.join_code)).id == event.id
      assert [%{id: id}] = Events.list_events()
      assert id == event.id
      assert {:error, cs} = Events.create_event(%{})
      assert "can't be blank" in errors_on(cs).name
    end

    test "admin token is generated, kept on update and never cast", %{event: event} do
      assert is_binary(event.admin_token) and String.length(event.admin_token) == 32

      {:ok, updated} = Events.update_event(event, %{"name" => "New", "admin_token" => "mine"})
      assert updated.admin_token == event.admin_token

      {:ok, other} = Events.create_event(%{name: "Other", admin_token: "mine"})
      refute other.admin_token in ["mine", event.admin_token]
    end

    test "get_event_for_admin needs the matching token", %{event: event} do
      assert Events.get_event_for_admin(event.id, event.admin_token).id == event.id
      assert Events.get_event_for_admin(to_string(event.id), event.admin_token).id == event.id
      assert Events.get_event_for_admin(event.id, "wrong") == nil
      assert Events.get_event_for_admin(event.id, nil) == nil
      assert Events.get_event_for_admin("abc", event.admin_token) == nil
      assert Events.get_event_for_admin(event.id + 1_000, event.admin_token) == nil
    end
  end

  describe "speeches" do
    test "create, list, start/end", %{event: event, speech: speech, speaker: speaker} do
      assert speech.speaker_id == speaker.id
      assert [%{id: id}] = Speeches.list_speeches(event.id)
      assert id == speech.id
      assert {:ok, s} = Speeches.start_speech(speech)
      assert s.started_at
      assert {:ok, s} = Speeches.end_speech(s)
      assert s.ended_at
      assert Speeches.get_speech_by_join_code(speech.join_code).id == speech.id
      assert {:error, cs} = Speeches.create_speech(%{title: "x", event_id: -1})
      assert "does not exist" in errors_on(cs).event
    end

    test "artifacts and transcript segments", %{speech: speech} do
      assert {:error, cs} = Speeches.create_artifact(%{kind: "video", speech_id: speech.id})
      assert "is invalid" in errors_on(cs).kind

      {:ok, t} = Speeches.create_artifact(%{kind: "transcript", speech_id: speech.id})
      {:ok, _} = Speeches.create_artifact(%{kind: "slides", url: "u", speech_id: speech.id})
      assert [%{kind: "transcript"}] = Speeches.list_artifacts(speech.id, "transcript")
      assert length(Speeches.list_artifacts(speech.id)) == 2

      {:ok, _} =
        Speeches.add_transcript_segment(%{
          artifact_id: t.id,
          text: "b",
          start_ms: 2000,
          end_ms: 3000
        })

      {:ok, _} =
        Speeches.add_transcript_segment(%{
          artifact_id: t.id,
          text: "a",
          start_ms: 0,
          end_ms: 1000
        })

      assert ["a", "b"] = Speeches.list_transcript_segments(t.id) |> Enum.map(& &1.text)

      assert {:error, cs} =
               Speeches.add_transcript_segment(%{
                 artifact_id: t.id,
                 text: "x",
                 start_ms: 5,
                 end_ms: 1
               })

      assert "must not be before start_ms" in errors_on(cs).end_ms
    end
  end

  describe "questions" do
    test "create, list, retract, group", %{speech: speech, attendee: a} do
      base = %{user_id: a.id, speech_id: speech.id}

      {:ok, q2} =
        Questions.create_question(
          Map.merge(base, %{text: "later", offset_ms: 9000, slide_number: 3})
        )

      {:ok, q1} = Questions.create_question(Map.merge(base, %{text: "early", offset_ms: 100}))
      assert ["early", "later"] = Questions.list_questions(speech.id) |> Enum.map(& &1.text)
      assert q2.slide_number == 3

      {:ok, q1} = Questions.retract_question(q1)
      assert q1.retracted_at
      assert [%{id: id}] = Questions.list_questions(speech.id)
      assert id == q2.id
      assert length(Questions.list_questions(speech.id, include_retracted: true)) == 2

      assert {:ok, %{group_id: 7}} = Questions.assign_group(q2, 7)
      assert Questions.get_question!(q2.id).group_id == 7

      assert {:error, cs} =
               Questions.create_question(
                 Map.merge(base, %{text: "x", offset_ms: -1, slide_number: 0})
               )

      assert errors_on(cs).offset_ms != []
      assert errors_on(cs).slide_number != []
    end
  end

  describe "notes" do
    test "create, update, list per user", %{speech: speech, attendee: a, speaker: s} do
      {:ok, n} = Notes.create_note(%{body: "hi", user_id: a.id, speech_id: speech.id})
      {:ok, _} = Notes.create_note(%{body: "other", user_id: s.id, speech_id: speech.id})
      assert [%{body: "hi"}] = Notes.list_notes(speech.id, a.id)
      assert {:ok, %{body: "hi!"}} = Notes.update_note(n, %{body: "hi!"})
      assert Notes.get_note!(n.id).body == "hi!"
    end
  end

  test "deleting an event cascades to speeches", %{event: event, speech: speech} do
    Repo.delete!(event)
    refute Speeches.get_speech(speech.id)
  end
end
