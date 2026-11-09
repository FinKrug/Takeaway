defmodule Takeaway.QuestionsTest do
  use Takeaway.DataCase, async: false

  alias Takeaway.{Accounts, Events, Questions, Speeches}

  setup do
    {:ok, event} = Events.create_event(%{name: "Conf"})
    started = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-90, :second)

    {:ok, speech} =
      Speeches.create_speech(%{title: "Talk", event_id: event.id, started_at: started})

    {:ok, user} = Accounts.create_anonymous_attendee()
    {:ok, other} = Accounts.create_anonymous_attendee()
    Questions.subscribe(speech.id)
    on_exit(fn -> Application.delete_env(:takeaway, :question_filter) end)
    %{speech: speech, user: user, other: other}
  end

  test "submit stamps offset and broadcasts", %{speech: s, user: u} do
    assert {:ok, q} = Questions.submit_question(s, u, %{"text" => "  Why?  "})
    assert q.text == "Why?"
    assert_in_delta q.offset_ms, 90_000, 3_000
    assert_receive {:question_created, %{id: id}}
    assert id == q.id
  end

  test "offset is 0 before speech starts", %{speech: s, user: u} do
    s = %{s | started_at: nil}
    assert {:ok, %{offset_ms: 0}} = Questions.submit_question(s, u, %{text: "hi"})
  end

  test "blank text is rejected and not broadcast", %{speech: s, user: u} do
    assert {:error, cs} = Questions.submit_question(s, u, %{"text" => " "})
    assert "can't be blank" in errors_on(cs).text
    refute_receive {:question_created, _}
  end

  test "filter hook can reject or rewrite", %{speech: s, user: u} do
    Application.put_env(:takeaway, :question_filter, fn
      "bad" -> {:error, :rejected}
      t -> {:ok, String.upcase(t)}
    end)

    assert {:error, :rejected} = Questions.submit_question(s, u, %{"text" => "bad"})
    refute_receive {:question_created, _}
    assert {:ok, %{text: "OK"}} = Questions.submit_question(s, u, %{"text" => "ok"})
  end

  test "question?/1 heuristic" do
    assert Questions.question?("Is this live?")
    assert Questions.question?("how does it scale")
    assert Questions.question?("Can you repeat that")
    assert Questions.question?("What's the latency")
    assert Questions.question?("So, how does it scale")
    assert Questions.question?("don\u2019t you think so")
    refute Questions.question?("Thanks everyone")
    refute Questions.question?("Whatever, moving on")
    refute Questions.question?("Have a great day everyone")
    refute Questions.question?("Do check out our booth")
    refute Questions.question?("Will is our CTO")
    refute Questions.question?("  ")
    refute Questions.question?(nil)
  end

  test "question?/1 does not call the submission filter" do
    Application.put_env(:takeaway, :question_filter, fn _ -> raise "filter called" end)
    assert Questions.question?("Is this live?")
  end

  test "list_question_segments returns only question segments", %{speech: s} do
    {:ok, _} =
      Takeaway.Transcripts.record_segments(s.id, [
        %{text: "Welcome all", start_ms: 0, end_ms: 500},
        %{text: "Does it scale?", start_ms: 500, end_ms: 900}
      ])

    assert ["Does it scale?"] =
             Enum.map(Takeaway.Transcripts.list_question_segments(s.id), & &1.text)
  end

  test "record_segments persists speaker labels", %{speech: s} do
    {:ok, [a, b]} =
      Takeaway.Transcripts.record_segments(s.id, [
        %{text: "Hello", start_ms: 0, end_ms: 500, speaker: "A"},
        %{text: "Hi", start_ms: 500, end_ms: 900}
      ])

    assert {a.speaker, b.speaker} == {"A", nil}
    assert ["A", nil] = Enum.map(Takeaway.Transcripts.list_segments(s.id), & &1.speaker)
  end

  test "owner retracts, broadcasts, disappears from list", %{speech: s, user: u, other: o} do
    {:ok, q} = Questions.submit_question(s, u, %{"text" => "Q"})
    assert_receive {:question_created, _}

    assert {:error, :forbidden} = Questions.retract_question_by(q.id, o)
    assert {:error, :not_found} = Questions.retract_question_by(-1, u)
    refute_receive {:question_retracted, _}

    assert {:ok, %{retracted_at: at}} = Questions.retract_question_by(q.id, u)
    assert at
    assert_receive {:question_retracted, %{id: id}}
    assert id == q.id
    assert Questions.list_questions(s.id) == []

    assert {:ok, _} = Questions.retract_question_by(q.id, u)
    refute_receive {:question_retracted, _}
  end
end
