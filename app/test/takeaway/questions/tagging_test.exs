defmodule Takeaway.Questions.TaggingTest do
  use Takeaway.DataCase, async: false
  alias Takeaway.{Accounts, Events, Questions, Speeches, Slides, Transcripts}
  alias Takeaway.Questions.{Tagging, TagWorker}

  setup do
    old = Application.fetch_env!(:takeaway, :elasticsearch)

    Application.put_env(
      :takeaway,
      :elasticsearch,
      Keyword.put(old, :request_options, plug: {Req.Test, __MODULE__})
    )

    on_exit(fn -> Application.put_env(:takeaway, :elasticsearch, old) end)
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{hits: %{hits: []}}) end)
    {:ok, event} = Events.create_event(%{name: "Context"})
    start = DateTime.utc_now(:second)

    {:ok, speech} =
      Speeches.create_speech(%{title: "Talk", event_id: event.id, started_at: start})

    {:ok, user} = Accounts.create_anonymous_attendee()
    Questions.subscribe(speech.id)
    %{speech: speech, user: user, now: DateTime.add(start, 65, :second)}
  end

  defp ask(ctx, attrs \\ %{}) do
    {:ok, question} =
      Questions.submit_question(
        ctx.speech,
        ctx.user,
        Map.merge(%{text: "How does distributed consensus work?"}, attrs),
        ctx.now
      )

    question
  end

  test "captures active transcript and explicit slide without changing submission time", ctx do
    {:ok, [segment]} =
      Transcripts.record_segments(
        ctx.speech.id,
        [%{text: "Distributed consensus works through voting", start_ms: 60_000, end_ms: 70_000}]
      )

    q = ask(ctx, %{slide_number: 4})
    assert q.offset_ms == 65_000
    assert q.context_segment_id == segment.id
    assert q.context_offset_ms == 60_000
    assert q.tag == "Slide 4 · 01:00"
  end

  test "without content the submission timestamp is the fallback, including before start", ctx do
    q = ask(ctx)
    assert q.tag == "01:05"
    assert q.context_segment_id == nil
    ctx = %{ctx | speech: %{ctx.speech | started_at: nil}}
    assert ask(ctx).tag == "00:00"
  end

  test "ES matches earlier transcript and slides but keeps original question offset", ctx do
    {:ok, [segment]} =
      Transcripts.record_segments(
        ctx.speech.id,
        [%{text: "Distributed consensus work", start_ms: 10_000, end_ms: 20_000}]
      )

    {:ok, _} = Slides.upsert_slides(ctx.speech.id, ["Distributed consensus work"])
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:search, Jason.decode!(body)})

      hits =
        case conn.request_path do
          "/transcript_segments/_search" -> [%{_id: to_string(segment.id)}]
          "/slides/_search" -> [%{_source: %{slide_number: 1}}]
        end

      Req.Test.json(conn, %{hits: %{hits: hits}})
    end)

    q = ask(ctx)
    tagged = Tagging.enrich(q.id)
    assert tagged.offset_ms == 65_000
    assert tagged.context_segment_id == segment.id
    assert tagged.tag == "Slide 1 · 00:10"
    assert_receive {:search, %{"query" => %{"bool" => %{"filter" => filters}}}}
    assert filters == [%{"term" => %{"speech_id" => to_string(ctx.speech.id)}}]
    assert_receive {:question_tagged, %{id: id, tag: "Slide 1 · 00:10"}}
    assert id == q.id
  end

  test "rejects stale or foreign ES candidates", ctx do
    {:ok, other} = Speeches.create_speech(%{title: "Other", event_id: ctx.speech.event_id})

    {:ok, [foreign]} =
      Transcripts.record_segments(
        other.id,
        [%{text: "Distributed consensus work", start_ms: 0, end_ms: 10_000}]
      )

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{hits: %{hits: [%{_id: to_string(foreign.id)}]}})
    end)

    q = ask(ctx)
    assert Tagging.enrich(q.id).context_segment_id == nil
  end

  test "search outage preserves saved question and explicit slide", ctx do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)
    q = ask(ctx, %{slide_number: 4})
    assert Tagging.enrich(q.id).tag == "Slide 4 · 01:05"
    assert Questions.get_question!(q.id).text == q.text
  end

  test "a semantic slide match cannot overwrite an attendee's explicit slide", ctx do
    {:ok, _} = Slides.upsert_slides(ctx.speech.id, ["Distributed consensus work"])

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{hits: %{hits: [%{_source: %{slide_number: 1}}]}})
    end)

    q = ask(ctx, %{slide_number: 4})
    assert q.slide_source == "manual"
    assert Tagging.enrich(q.id).slide_number == 4
  end

  test "index updates read current tags and never recreate a retracted question", ctx do
    q = ask(ctx)
    updated = q |> Ecto.Changeset.change(tag: "Slide 4 · 00:10") |> Repo.update!()
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:index, conn.method, body})
      Req.Test.json(conn, %{result: "ok"})
    end)

    state = %{auto_sync: false}
    Takeaway.Elasticsearch.QuestionSync.handle_info({:question_created, q}, state)
    assert_receive {:index, "PUT", body}
    assert Jason.decode!(body)["tag"] == updated.tag
    assert {:ok, _} = Questions.retract_question_by(q.id, ctx.user)
    Takeaway.Elasticsearch.QuestionSync.handle_info({:question_tagged, updated}, state)
    assert_receive {:index, "DELETE", _}
    refute_receive {:index, "PUT", _}
  end

  test "late transcript updates context, and retraction cannot be undone", ctx do
    q = ask(ctx)

    {:ok, [segment]} =
      Transcripts.record_segments(
        ctx.speech.id,
        [%{text: "Consensus requires votes", start_ms: 60_000, end_ms: 70_000}]
      )

    Tagging.attach_delayed(ctx.speech.id, segment)
    assert Questions.get_question!(q.id).context_segment_id == segment.id
    assert {:ok, _} = Questions.retract_question_by(q.id, ctx.user)
    assert Tagging.enrich(q.id) == nil
    assert Questions.list_questions(ctx.speech.id) == []
  end

  test "worker handles delayed transcript events without an ES request", ctx do
    worker = start_supervised!({TagWorker, enabled: true, name: nil})
    Req.Test.allow(__MODULE__, self(), worker)
    q = ask(ctx)
    :sys.get_state(worker)

    {:ok, [segment]} =
      Transcripts.record_segments(
        ctx.speech.id,
        [%{text: "Consensus requires votes", start_ms: 60_000, end_ms: 70_000}]
      )

    :sys.get_state(worker)
    assert Questions.get_question!(q.id).context_segment_id == segment.id
  end
end
