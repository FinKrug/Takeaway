defmodule Takeaway.Elasticsearch.QuestionSyncTest do
  use ExUnit.Case, async: false

  alias Takeaway.Elasticsearch.QuestionSync
  alias Takeaway.Questions

  setup do
    old = Application.fetch_env!(:takeaway, :elasticsearch)

    Application.put_env(
      :takeaway,
      :elasticsearch,
      Keyword.put(old, :request_options, plug: {Req.Test, __MODULE__})
    )

    on_exit(fn -> Application.put_env(:takeaway, :elasticsearch, old) end)
    Application.ensure_all_started(:phoenix_pubsub)

    case Process.whereis(Takeaway.PubSub) do
      nil -> start_supervised!({Phoenix.PubSub, name: Takeaway.PubSub})
      _pid -> :ok
    end

    :ok
  end

  describe "QuestionSync initialization and event handling" do
    test "starts and subscribes to global questions topic when auto_sync is enabled" do
      pid = start_supervised!({QuestionSync, auto_sync: true, name: nil})
      test_pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        send(test_pid, {:es_request, conn.method, conn.request_path})
        Req.Test.json(conn, %{result: "created"})
      end)

      Req.Test.allow(__MODULE__, self(), pid)

      Phoenix.PubSub.broadcast(
        Takeaway.PubSub,
        Questions.global_topic(),
        {:question_created, %{id: 42, speech_id: 9, text: "Why?"}}
      )

      :sys.get_state(pid)
      assert_receive {:es_request, "PUT", "/questions/_doc/42"}
    end

    test "handles :question_created and :question_retracted without crashing" do
      state = %{auto_sync: false}
      test_pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        send(test_pid, {:es_request, conn.method, conn.request_path})
        Req.Test.json(conn, %{result: "ok"})
      end)

      question = %{
        id: "q_test_123",
        speech_id: "speech_456",
        user_id: "user_789",
        text: "What are the latency tradeoffs?",
        offset_ms: 5000,
        slide_number: 2
      }

      assert {:noreply, ^state} =
               QuestionSync.handle_info({:question_created, question}, state)

      assert_receive {:es_request, "PUT", "/questions/_doc/q_test_123"}

      assert {:noreply, ^state} =
               QuestionSync.handle_info({:question_retracted, question}, state)

      assert_receive {:es_request, "DELETE", "/questions/_doc/q_test_123"}
    end

    test "ignores unexpected messages" do
      state = %{auto_sync: false}
      assert {:noreply, ^state} = QuestionSync.handle_info(:unknown_event, state)
    end
  end

  describe "Questions global topic broadcast" do
    test "global_topic returns questions:all" do
      assert Questions.global_topic() == "questions:all"
    end
  end
end
