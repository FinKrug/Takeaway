defmodule Takeaway.ElasticsearchTest do
  use ExUnit.Case, async: true

  alias Takeaway.Elasticsearch

  describe "client configuration" do
    test "builds Req client with default settings" do
      client = Elasticsearch.client()
      assert %Req.Request{} = client
      assert client.options[:base_url] =~ "http"
    end
  end

  describe "live elasticsearch operations" do
    @describetag :elasticsearch

    setup do
      # Initialize test index
      test_index = "test_questions_#{System.unique_integer([:positive])}"

      schema = %{
        mappings: %{
          properties: %{
            speech_id: %{type: "keyword"},
            user_id: %{type: "keyword"},
            text: %{type: "text"},
            offset_ms: %{type: "integer"},
            slide_number: %{type: "integer"},
            tag: %{type: "keyword"},
            inserted_at: %{type: "date"}
          }
        }
      }

      on_exit(fn ->
        Elasticsearch.delete_index(test_index)
      end)

      {:ok, %{test_index: test_index, schema: schema}}
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
  end
end
