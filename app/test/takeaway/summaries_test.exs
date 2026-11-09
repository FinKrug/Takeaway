defmodule Takeaway.SummariesTest do
  # Mutates application env, so not async.
  use Takeaway.DataCase, async: false

  alias Takeaway.{Accounts, Events, Notes, Questions, Speeches, Summaries, Transcripts}

  setup do
    {:ok, event} = Events.create_event(%{name: "Conf"})
    {:ok, speaker} = Accounts.create_speaker(%{name: "Sam"})
    {:ok, attendee} = Accounts.create_anonymous_attendee()

    {:ok, speech} =
      Speeches.create_speech(%{title: "Talk", event_id: event.id, speaker_id: speaker.id})

    Application.put_env(:takeaway, :llm, Takeaway.FakeLLM)
    Application.put_env(:takeaway, :llm_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:takeaway, :llm)
      Application.delete_env(:takeaway, :llm_test_pid)
    end)

    %{speech: speech, attendee: attendee}
  end

  defp ended(speech) do
    {:ok, s} =
      Speeches.update_speech(speech, %{
        started_at: ~U[2026-01-01 10:00:00Z],
        ended_at: ~U[2026-01-01 10:10:00Z]
      })

    s
  end

  defp ask(speech, user, text, offset_ms, group_id \\ nil) do
    {:ok, q} =
      Questions.create_question(%{
        text: text,
        offset_ms: offset_ms,
        group_id: group_id,
        user_id: user.id,
        speech_id: speech.id
      })

    q
  end

  test "not available before the speech ends", %{speech: speech, attendee: a} do
    assert {:error, :not_ended} = Summaries.speaker_summary(speech)
    assert {:error, :not_ended} = Summaries.attendee_summary(speech, a.id)
  end

  test "speaker summary has groups and spikes, and is generated once", %{
    speech: speech,
    attendee: a
  } do
    Transcripts.record_segments(speech.id, [
      %{text: "We talk about OTP", start_ms: 0, end_ms: 900}
    ])

    ask(speech, a, "What is OTP?", 100_000, 1)
    ask(speech, a, "Explain OTP again", 110_000, 1)
    ask(speech, a, "Is it fast?", 120_000, 2)
    ask(speech, a, "Lone question", 500_000)
    speech = ended(speech)

    assert {:ok, s} = Summaries.speaker_summary(speech)
    assert s.kind == "speaker"
    assert s.content["summary"] =~ "AI:"
    assert s.content["total_questions"] == 4
    assert s.content["has_transcript"]
    assert [%{"count" => 2, "label" => "What is OTP?"} | _] = s.content["question_groups"]

    assert [%{"count" => 2, "start_ms" => 60_000, "end_ms" => 120_000}] =
             s.content["question_spikes"]

    assert_received {:llm_called, _, prompt}
    assert prompt =~ "We talk about OTP"
    assert prompt =~ "What is OTP?"

    # cached: no second LLM call, same row
    assert {:ok, again} = Summaries.speaker_summary(speech)
    assert again.id == s.id
    refute_received {:llm_called, _, _}
  end

  test "speaker summary with no transcript and no questions", %{speech: speech} do
    assert {:ok, s} = Summaries.speaker_summary(ended(speech))
    assert s.content["summary"] =~ "nothing to summarize"
    assert s.content["question_groups"] == []
    assert s.content["question_spikes"] == []
    refute s.content["has_transcript"]
    refute_received {:llm_called, _, _}
  end

  test "speaker summary with questions but no transcript", %{speech: speech, attendee: a} do
    ask(speech, a, "Hello?", 1000)
    assert {:ok, s} = Summaries.speaker_summary(ended(speech))
    assert s.content["summary"] =~ "AI:"
    assert_received {:llm_called, _, prompt}
    assert prompt =~ "no transcript was recorded"
  end

  test "falls back to an extractive summary when the LLM fails", %{speech: speech} do
    Application.put_env(:takeaway, :llm, Takeaway.FailingLLM)
    Transcripts.record_segments(speech.id, [%{text: "Some content", start_ms: 0, end_ms: 100}])
    assert {:ok, s} = Summaries.speaker_summary(ended(speech))
    assert s.content["summary"] =~ "Talk excerpt: Some content"
    assert s.generated_by == "extractive"
  end

  test "attendee summary merges their own notes and is cached per user", %{
    speech: speech,
    attendee: a
  } do
    {:ok, other} = Accounts.create_anonymous_attendee()

    Transcripts.record_segments(speech.id, [
      %{text: "Supervisors restart", start_ms: 0, end_ms: 9}
    ])

    {:ok, _} =
      Notes.create_note(%{body: "remember supervisors", user_id: a.id, speech_id: speech.id})

    speech = ended(speech)

    assert {:ok, s} = Summaries.attendee_summary(speech, a.id)
    assert s.kind == "attendee"
    assert s.content["notes"] == ["remember supervisors"]
    assert_received {:llm_called, _, prompt}
    assert prompt =~ "Supervisors restart"
    assert prompt =~ "remember supervisors"

    assert {:ok, %{id: id}} = Summaries.attendee_summary(speech, a.id)
    assert id == s.id
    refute_received {:llm_called, _, _}

    # another attendee gets their own, without the first one's notes
    assert {:ok, o} = Summaries.attendee_summary(speech, other.id)
    assert o.id != s.id
    assert o.content["notes"] == []
  end

  test "attendee summary with no transcript and no notes", %{speech: speech, attendee: a} do
    assert {:ok, s} = Summaries.attendee_summary(ended(speech), a.id)
    assert s.content["cliffnotes"] =~ "No transcript was recorded"
    refute_received {:llm_called, _, _}
  end

  test "spikes need at least two questions in a bucket", %{speech: speech, attendee: a} do
    qs = [ask(speech, a, "one", 0), ask(speech, a, "two", 300_000)]
    assert Summaries.question_spikes(ended(speech), qs, []) == []
  end

  test "end_speech is idempotent and broadcasts once", %{speech: speech} do
    Takeaway.SpeechCreator.subscribe(speech.id)
    assert {:ok, e} = Takeaway.SpeechCreator.end_speech(speech)
    assert e.ended_at
    assert_receive {:speech_ended, _}
    assert {:ok, e2} = Takeaway.SpeechCreator.end_speech(e)
    assert e2.ended_at == e.ended_at
    refute_receive {:speech_ended, _}
  end
end
