defmodule Takeaway.Questions.GroupingTest do
  use Takeaway.DataCase, async: false
  alias Takeaway.{Accounts, Events, Questions, Speeches}
  alias Takeaway.Questions.{Group, Grouping, GroupWorker}

  setup do
    old = Application.fetch_env!(:takeaway, :elasticsearch)

    Application.put_env(
      :takeaway,
      :elasticsearch,
      Keyword.put(old, :request_options, plug: {Req.Test, __MODULE__})
    )

    on_exit(fn -> Application.put_env(:takeaway, :elasticsearch, old) end)
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{hits: %{hits: []}}) end)
    {:ok, event} = Events.create_event(%{name: "Conf"})
    {:ok, speech} = Speeches.create_speech(%{title: "Talk", event_id: event.id})
    {:ok, user} = Accounts.create_anonymous_attendee()
    %{speech: speech, user: user}
  end

  defp question(ctx, text) do
    {:ok, q} = Questions.submit_question(ctx.speech, ctx.user, %{text: text})
    q
  end

  test "near duplicates group through the ES refresh gap; unrelated questions stay separate",
       ctx do
    a = question(ctx, "How does distributed consensus work?")
    b = question(ctx, "Can you explain distributed consensus?")
    c = question(ctx, "What is the memory allocation limit?")
    assert {:ok, grouped_a} = Grouping.assign(a)
    assert {:ok, grouped_b} = Grouping.assign(b)
    assert {:ok, grouped_c} = Grouping.assign(c)
    assert grouped_a.group_id == grouped_b.group_id
    refute grouped_c.group_id == grouped_a.group_id
    assert [%{count: 2}, %{count: 1}] = Questions.list_top_groups(ctx.speech.id)

    assert [%{"count" => 2}, %{"count" => 1}] =
             ctx.speech.id |> Questions.list_questions() |> Takeaway.Summaries.question_groups()
  end

  test "tied counts use earliest active question and respect the limit", ctx do
    first = question(ctx, "Why does zebra scheduling fail?")
    second = question(ctx, "How does alpha replication work?")
    assert {:ok, _} = Grouping.assign(first)
    assert {:ok, _} = Grouping.assign(second)
    assert [%{text: first_text}, %{text: second_text}] = Questions.list_top_groups(ctx.speech.id)
    assert first_text == first.text
    assert second_text == second.text
    assert [%{text: ^first_text}] = Questions.list_top_groups(ctx.speech.id, limit: 1)
    assert {:ok, _} = Questions.retract_question_by(first.id, ctx.user)
    assert [%{text: ^second_text, count: 1}] = Questions.list_top_groups(ctx.speech.id)
  end

  test "a group of three drops to two and then disappears after the last retraction", ctx do
    questions = for _ <- 1..3, do: question(ctx, "How does distributed consensus work?")
    Enum.each(questions, &Grouping.assign/1)
    assert [%{count: 3}] = Questions.list_top_groups(ctx.speech.id)
    [first | rest] = questions
    {:ok, retracted} = Questions.retract_question_by(first.id, ctx.user)
    Grouping.retract(retracted)
    assert [%{count: 2, text: representative}] = Questions.list_top_groups(ctx.speech.id)
    assert representative == hd(rest).text

    for q <- rest do
      {:ok, retracted} = Questions.retract_question_by(q.id, ctx.user)
      Grouping.retract(retracted)
    end

    assert Questions.list_top_groups(ctx.speech.id) == []
    assert Repo.aggregate(from(g in Group, where: g.speech_id == ^ctx.speech.id), :count) == 0
  end

  test "labelled 40-question sample has no false merges or missed groups", ctx do
    sample =
      Path.expand("../../fixtures/question_grouping.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    assigned =
      for row <- sample do
        q = question(ctx, row["text"])
        assert {:ok, grouped} = Grouping.assign(q)
        {row["group"], grouped.group_id}
      end

    pairs =
      for {a, i} <- Enum.with_index(assigned), {b, j} <- Enum.with_index(assigned), i < j do
        {elem(a, 0) == elem(b, 0), elem(a, 1) == elem(b, 1)}
      end

    true_positives = Enum.count(pairs, &(&1 == {true, true}))
    false_positives = Enum.count(pairs, &(&1 == {false, true}))
    false_negatives = Enum.count(pairs, &(&1 == {true, false}))
    assert length(sample) == 40
    assert length(pairs) == 780
    assert true_positives == 80
    assert false_positives == 0
    assert false_negatives == 0
    assert Enum.map(Questions.list_top_groups(ctx.speech.id), & &1.count) == List.duplicate(5, 8)
  end

  test "rejects stale and foreign search hits", ctx do
    {:ok, foreign} = Speeches.create_speech(%{title: "Other", event_id: ctx.speech.event_id})
    outsider = question(%{ctx | speech: foreign}, "How does distributed consensus work?")
    stale = question(ctx, "How does distributed consensus work?")
    {:ok, _} = Questions.retract_question_by(stale.id, ctx.user)

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        hits: %{hits: [%{_id: to_string(outsider.id)}, %{_id: to_string(stale.id)}]}
      })
    end)

    fresh = question(ctx, "How does distributed consensus work?")
    assert {:ok, grouped} = Grouping.assign(fresh)
    assert [%{count: 1}] = Questions.list_top_groups(ctx.speech.id)
    assert Repo.get!(Takeaway.Questions.Question, outsider.id).group_id == nil
    assert grouped.group_id
  end

  test "search outage saves and displays singleton questions", ctx do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)
    a = question(ctx, "How does distributed consensus work?")
    b = question(ctx, "How does distributed consensus work?")
    assert {:ok, ga} = Grouping.assign(a)
    assert {:ok, gb} = Grouping.assign(b)
    refute ga.group_id == gb.group_id
    assert [%{count: 1}, %{count: 1}] = Questions.list_top_groups(ctx.speech.id)
  end

  test "duplicate assignment and repeated retract events cannot corrupt counts", ctx do
    a = question(ctx, "How does distributed consensus work?")
    assert {:ok, ga} = Grouping.assign(a)
    assert {:ok, again} = Grouping.assign(a)
    assert ga.group_id == again.group_id
    b = question(ctx, "Explain distributed consensus work?")
    assert {:ok, _} = Grouping.assign(b)
    {:ok, retracted_a} = Questions.retract_question_by(a.id, ctx.user)
    assert {:ok, _} = Grouping.retract(retracted_a)

    assert [%{text: "Explain distributed consensus work?", count: 1}] =
             Questions.list_top_groups(ctx.speech.id)

    {:ok, retracted_b} = Questions.retract_question_by(b.id, ctx.user)
    assert {:ok, _} = Grouping.retract(retracted_b)
    assert {:ok, _} = Grouping.retract(retracted_b)
    assert [] = Questions.list_top_groups(ctx.speech.id)
    assert Repo.get(Group, ga.group_id) == nil
    assert {:ok, %{retracted_at: %DateTime{}, group_id: nil}} = Grouping.assign(b)
  end

  test "background worker processes PubSub without blocking submit", ctx do
    worker = start_supervised!({GroupWorker, enabled: true, name: nil})
    Req.Test.allow(__MODULE__, self(), worker)
    q = question(ctx, "How does distributed consensus work?")
    :sys.get_state(worker)
    assert Questions.get_question(q.id).group_id
  end

  test "verbal questions group without a user", ctx do
    {:ok, q} =
      Questions.create_question(%{
        text: "How does distributed consensus work?",
        speech_id: ctx.speech.id,
        source: "verbal"
      })

    assert {:ok, %{group_id: id}} = Grouping.assign(q)
    assert id
  end

  test "simultaneous assignments on separate database connections create one group" do
    supervisor = start_supervised!({Task.Supervisor, []})

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      {:ok, event} = Events.create_event(%{name: "Concurrency test"})
      {:ok, speech} = Speeches.create_speech(%{title: "Race", event_id: event.id})
      {:ok, user} = Accounts.create_anonymous_attendee()

      try do
        ctx = %{speech: speech, user: user}
        a = question(ctx, "How does distributed consensus work?")
        b = question(ctx, "Explain distributed consensus work?")

        tasks =
          Enum.map([a, b], fn q ->
            Task.Supervisor.async_nolink(supervisor, fn ->
              receive do
                :go -> Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> Grouping.assign(q) end)
              end
            end)
          end)

        Enum.each(tasks, fn task ->
          Req.Test.allow(__MODULE__, self(), task.pid)
          send(task.pid, :go)
        end)

        assert [{:ok, ga}, {:ok, gb}] = Enum.map(tasks, &Task.await/1)
        assert ga.group_id == gb.group_id
        assert [%{count: 2}] = Questions.list_top_groups(speech.id)
        assert Repo.aggregate(from(g in Group, where: g.speech_id == ^speech.id), :count) == 1
      after
        Repo.delete_all(from q in Takeaway.Questions.Question, where: q.speech_id == ^speech.id)
        Repo.delete_all(from g in Group, where: g.speech_id == ^speech.id)
        Repo.delete!(speech)
        Repo.delete!(event)
        Repo.delete!(user)
      end
    end)
  end

  test "similarity rejects generic wording and distinguishes topics" do
    assert Grouping.similarity(
             "How does distributed consensus work?",
             "Explain distributed consensus work"
           ) == 1.0

    assert Grouping.similarity("Why?", "Why?") == 0.0

    assert Grouping.similarity(
             "How does memory allocation work?",
             "How does distributed consensus work?"
           ) < 0.6

    assert Grouping.similarity(
             "¿Cómo funciona consenso distribuido?",
             "Cómo funciona consenso distribuido"
           ) == 1.0
  end

  test "0.6 threshold separates a small sample of related and unrelated questions" do
    related = [
      {"How does distributed consensus work?", "Explain distributed consensus work?"},
      {"What are memory allocation limits?", "Explain memory allocation limits?"},
      {"How do database replicas handle failures?", "Can database replicas handle failures?"}
    ]

    unrelated = [
      {"How does distributed consensus work?", "How does memory allocation work?"},
      {"What are memory allocation limits?", "What are database connection limits?"},
      {"Why?", "Why?"}
    ]

    for {a, b} <- related, do: assert(Grouping.similarity(a, b) >= 0.6)
    for {a, b} <- unrelated, do: assert(Grouping.similarity(a, b) < 0.6)
  end
end
