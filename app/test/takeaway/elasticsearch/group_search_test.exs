defmodule Takeaway.Elasticsearch.GroupSearchTest do
  use ExUnit.Case, async: false
  alias Takeaway.Elasticsearch

  setup do
    old = Application.fetch_env!(:takeaway, :elasticsearch)

    Application.put_env(
      :takeaway,
      :elasticsearch,
      Keyword.put(old, :request_options, plug: {Req.Test, __MODULE__})
    )

    on_exit(fn -> Application.put_env(:takeaway, :elasticsearch, old) end)
    :ok
  end

  test "similarity search is scoped to one speech and requests selective term overlap" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/questions/_search"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      query = Jason.decode!(body)
      assert query["query"]["bool"]["filter"] == [%{"term" => %{"speech_id" => "123"}}]
      assert [%{"more_like_this" => mlt}] = query["query"]["bool"]["must"]
      assert mlt["like"] == "distributed consensus"
      assert mlt["minimum_should_match"] == "70%"
      Req.Test.json(conn, %{hits: %{hits: []}})
    end)

    assert {:ok, %{"hits" => []}} =
             Elasticsearch.more_like_this_question(123, "distributed consensus")
  end

  test "Elasticsearch requests have bounded timeouts and no automatic retries" do
    client = Elasticsearch.client()
    assert client.options[:connect_options] == [timeout: 5_000]
    assert client.options[:receive_timeout] == 5_000
    assert client.options[:request_timeout] == 5_000
    assert client.options[:retry] == false
  end

  test "boot detects incompatible mappings instead of silently accepting an existing index" do
    Req.Test.stub(__MODULE__, fn conn ->
      case conn.method do
        "HEAD" ->
          Plug.Conn.send_resp(conn, 200, "")

        "GET" ->
          Req.Test.json(conn, %{
            questions: %{mappings: %{properties: %{speech_id: %{type: "text"}}}}
          })
      end
    end)

    assert {:error, {:mapping_drift, "questions", fields}} = Elasticsearch.init_indices()
    assert :speech_id in fields
  end
end
