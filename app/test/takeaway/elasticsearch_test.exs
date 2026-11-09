defmodule Takeaway.ElasticsearchTest do
  use ExUnit.Case, async: true

  alias Takeaway.Elasticsearch

  describe "client configuration and validation" do
    test "builds Req client with default settings" do
      client = Elasticsearch.client()
      assert %Req.Request{} = client
      assert client.options[:base_url] =~ "http"
    end

    test "validates required IDs before indexing" do
      assert {:error, :missing_id} = Elasticsearch.index_document("any_index", nil, %{})
      assert {:error, :missing_id} = Elasticsearch.index_document("any_index", "", %{})
      assert {:error, :missing_id} = Elasticsearch.delete_document("any_index", nil)
      assert {:error, :missing_id} = Elasticsearch.delete_document("any_index", "")

      assert {:error, :missing_id} = Elasticsearch.index_question(%{text: "Question without ID?"})
      assert {:error, :missing_id} = Elasticsearch.delete_question(nil)

      assert {:error, :missing_id} = Elasticsearch.index_transcript_segment(%{text: "Chunk"})

      assert {:error, :missing_speech_id} = Elasticsearch.index_slide(%{content: "Slide content"})
      assert {:error, :missing_slide_number} = Elasticsearch.index_slide(%{speech_id: "speech_1"})

      assert {:error, :missing_id} = Elasticsearch.index_note(%{body: "Note without ID"})
      assert {:error, :missing_id} = Elasticsearch.delete_note(nil)
    end
  end

  describe "live elasticsearch operations" do
    @describetag :elasticsearch

    setup do
      # Initialize isolated test indices
      unique_id = System.unique_integer([:positive])
      test_index = "test_questions_#{unique_id}"
      test_notes_index = "test_notes_#{unique_id}"

      schema = Elasticsearch.mapping_for("questions")
      notes_schema = Elasticsearch.mapping_for("notes")

      on_exit(fn ->
        Elasticsearch.delete_index(test_index)
        Elasticsearch.delete_index(test_notes_index)
      end)

      {:ok,
       %{
         test_index: test_index,
         schema: schema,
         test_notes_index: test_notes_index,
         notes_schema: notes_schema
       }}
    end

    test "creates and verifies index existence", %{test_index: test_index, schema: schema} do
      assert Elasticsearch.index_exists?(test_index) == false
      assert {:ok, _} = Elasticsearch.create_index(test_index, schema)
      assert Elasticsearch.index_exists?(test_index) == true
    end

    test "indexes, gets, searches, and deletes a document", %{
      test_index: test_index,
      schema: schema
    } do
      {:ok, _} = Elasticsearch.create_index(test_index, schema)

      doc = %{
        speech_id: "speech_101",
        user_id: "user_42",
        text: "How does distributed consensus work with Raft?",
        offset_ms: 12500,
        slide_number: 4
      }

      # Index doc with refresh: true so it is immediately searchable
      assert {:ok, _} = Elasticsearch.index_document(test_index, "q1", doc, refresh: true)

      # Get document
      assert {:ok, source} = Elasticsearch.get_document(test_index, "q1")
      assert source["text"] == "How does distributed consensus work with Raft?"
      assert source["speech_id"] == "speech_101"

      # Search
      search_query = %{
        query: %{
          bool: %{
            must: [%{match: %{text: "consensus Raft"}}],
            filter: [%{term: %{speech_id: "speech_101"}}]
          }
        }
      }

      assert {:ok, %{"total" => %{"value" => total}, "hits" => [hit | _]}} =
               Elasticsearch.search(test_index, search_query)

      assert total >= 1
      assert hit["_id"] == "q1"

      # Delete document
      assert {:ok, _} = Elasticsearch.delete_document(test_index, "q1", refresh: true)
      assert {:error, :not_found} = Elasticsearch.get_document(test_index, "q1")
    end

    test "indexes, searches, and deletes notes using isolated index", %{
      test_notes_index: test_notes_index,
      notes_schema: notes_schema
    } do
      {:ok, _} = Elasticsearch.create_index(test_notes_index, notes_schema)

      note = %{
        id: "note_#{System.unique_integer([:positive])}",
        speech_id: "speech_999",
        user_id: "user_77",
        body: "Remember to review CAP theorem trade-offs from slide 3",
        offset_ms: 45000,
        slide_number: 3
      }

      assert {:ok, _} = Elasticsearch.index_note(note, index: test_notes_index, refresh: true)

      assert {:ok, %{"total" => %{"value" => total}, "hits" => [hit | _]}} =
               Elasticsearch.search_notes("speech_999", "user_77", "CAP theorem",
                 index: test_notes_index
               )

      assert total >= 1
      assert hit["_source"]["body"] =~ "CAP theorem"

      assert {:ok, _} = Elasticsearch.delete_note(note.id, index: test_notes_index, refresh: true)
    end
  end
end
