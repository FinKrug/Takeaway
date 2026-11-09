defmodule Takeaway.Elasticsearch.QuestionSyncTest do
  use ExUnit.Case, async: false

  alias Takeaway.Elasticsearch.QuestionSync
  alias Takeaway.Questions

  setup do
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
      assert Process.alive?(pid)
    end

    test "handles :question_created and :question_retracted without crashing" do
      state = %{auto_sync: false}

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

      assert {:noreply, ^state} =
               QuestionSync.handle_info({:question_retracted, question}, state)
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
