defmodule Takeaway.Elasticsearch do
  @moduledoc """
  Client module for interacting with Elasticsearch via Req.

  Provides functions for index management, document indexing, deletion,
  and searching across questions, transcript segments, and slides.
  """

  require Logger

  @questions_index "questions"
  @transcripts_index "transcript_segments"
  @slides_index "slides"
  @notes_index "notes"

  @indices [
    {@questions_index,
     %{
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
     }},
    {@transcripts_index,
     %{
       mappings: %{
         properties: %{
           speech_id: %{type: "keyword"},
           segment_id: %{type: "keyword"},
           text: %{type: "text"},
           start_ms: %{type: "integer"},
           end_ms: %{type: "integer"},
           slide_number: %{type: "integer"}
         }
       }
     }},
    {@slides_index,
     %{
       mappings: %{
         properties: %{
           speech_id: %{type: "keyword"},
           slide_number: %{type: "integer"},
           title: %{type: "text"},
           content: %{type: "text"}
         }
       }
     }},
    {@notes_index,
     %{
       mappings: %{
         properties: %{
           speech_id: %{type: "keyword"},
           user_id: %{type: "keyword"},
           body: %{type: "text"},
           offset_ms: %{type: "integer"},
           slide_number: %{type: "integer"},
           inserted_at: %{type: "date"},
           updated_at: %{type: "date"}
         }
       }
     }}
  ]

  @doc """
  Returns the configured base Req request for Elasticsearch.
  """
  def client do
    config = Application.get_env(:takeaway, :elasticsearch, [])
    url = Keyword.get(config, :url, "http://localhost:9200")
    api_key = Keyword.get(config, :api_key)

    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    headers =
      if api_key && api_key != "" do
        [{"authorization", "ApiKey #{api_key}"} | headers]
      else
        headers
      end

    Req.new(base_url: url, headers: headers)
  end

  @doc """
  Checks Elasticsearch cluster health.
  """
  def health do
    case Req.get(client(), url: "/_cluster/health") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if an index exists.
  """
  def index_exists?(index_name) do
    case Req.head(client(), url: "/#{index_name}") do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  @doc """
  Creates an index with given mapping definition.
  """
  def create_index(index_name, body \\ %{}) do
    case Req.put(client(), url: "/#{index_name}", json: body) do
      {:ok, %{status: 200, body: resp}} ->
        {:ok, resp}

      {:ok, %{status: 400, body: %{"error" => %{"type" => "resource_already_exists_exception"}}}} ->
        {:ok, :already_exists}

      {:ok, %{status: status, body: resp}} ->
        {:error, {:status, status, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes an index.
  """
  def delete_index(index_name) do
    case Req.delete(client(), url: "/#{index_name}") do
      {:ok, %{status: 200, body: resp}} -> {:ok, resp}
      {:ok, %{status: 404}} -> {:ok, :not_found}
      {:ok, %{status: status, body: resp}} -> {:error, {:status, status, resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Ensures all required indices exist with proper mappings.
  """
  def init_indices do
    Enum.reduce_while(@indices, :ok, fn {index_name, schema}, :ok ->
      case Req.head(client(), url: "/#{index_name}") do
        {:ok, %{status: 200}} ->
          {:cont, :ok}

        {:ok, %{status: 404}} ->
          Logger.info("[Elasticsearch] Creating index: #{index_name}")

          case create_index(index_name, schema) do
            {:ok, _} -> {:cont, :ok}
            err -> {:halt, err}
          end

        {:ok, %{status: status}} ->
          {:halt, {:error, {:status, status}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Returns the mapping definition for a known index name.
  """
  def mapping_for(index_name) do
    case List.keyfind(@indices, to_string(index_name), 0) do
      {_, schema} -> schema
      nil -> nil
    end
  end

  @doc """
  Indexes a document into the specified index.
  Opts:
    - `:refresh` - boolean (default false). When true, forces immediate index refresh.
  """
  def index_document(index_name, id, document, opts \\ []) do
    id_str = if id, do: to_string(id), else: ""

    if id_str == "" do
      {:error, :missing_id}
    else
      params = if Keyword.get(opts, :refresh, false), do: [refresh: "true"], else: []

      req = client()
      url = "/#{index_name}/_doc/#{id_str}"

      case Req.put(req, url: url, params: params, json: document) do
        {:ok, %{status: status, body: resp}} when status in [200, 201] ->
          {:ok, resp}

        {:ok, %{status: status, body: resp}} ->
          {:error, {:status, status, resp}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Fetches a document by id.
  """
  def get_document(index_name, id) do
    id_str = if id, do: to_string(id), else: ""

    if id_str == "" do
      {:error, :missing_id}
    else
      case Req.get(client(), url: "/#{index_name}/_doc/#{id_str}") do
        {:ok, %{status: 200, body: %{"_source" => source}}} ->
          {:ok, source}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status, body: resp}} ->
          {:error, {:status, status, resp}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Deletes a document by id.
  """
  def delete_document(index_name, id, opts \\ []) do
    id_str = if id, do: to_string(id), else: ""

    if id_str == "" do
      {:error, :missing_id}
    else
      params = if Keyword.get(opts, :refresh, false), do: [refresh: "true"], else: []

      case Req.delete(client(), url: "/#{index_name}/_doc/#{id_str}", params: params) do
        {:ok, %{status: 200, body: resp}} ->
          {:ok, resp}

        {:ok, %{status: 404}} ->
          {:ok, :not_found}

        {:ok, %{status: status, body: resp}} ->
          {:error, {:status, status, resp}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Executes a search query against an index.
  """
  def search(index_name, query_body) do
    case Req.post(client(), url: "/#{index_name}/_search", json: query_body) do
      {:ok, %{status: 200, body: %{"hits" => hits}}} ->
        {:ok, hits}

      {:ok, %{status: status, body: resp}} ->
        {:error, {:status, status, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # =========================================================================
  # Domain Functions: Questions
  # =========================================================================

  @doc """
  Indexes a question.
  Accepts either a map with string/atom keys or a struct.
  """
  def index_question(question, opts \\ []) do
    doc = normalize_question(question)
    id = doc[:id] || doc["id"]

    if is_nil(id) or id == "" do
      {:error, :missing_id}
    else
      index = Keyword.get(opts, :index, @questions_index)
      index_document(index, to_string(id), doc, opts)
    end
  end

  @doc """
  Removes a question from the index.
  """
  def delete_question(question_id, opts \\ []) do
    if is_nil(question_id) or question_id == "" do
      {:error, :missing_id}
    else
      index = Keyword.get(opts, :index, @questions_index)
      delete_document(index, to_string(question_id), opts)
    end
  end

  @doc """
  Searches questions for a given speech.
  """
  def search_questions(speech_id, query_text, opts \\ []) do
    index = Keyword.get(opts, :index, @questions_index)

    query = %{
      query: %{
        bool: %{
          must: [
            %{match: %{text: query_text}}
          ],
          filter: [
            %{term: %{speech_id: to_string(speech_id)}}
          ]
        }
      }
    }

    search(index, query)
  end

  @doc """
  Finds questions similar to the given text within a speech using Elasticsearch more_like_this.
  Used for question grouping (Card 300).
  """
  def more_like_this_question(speech_id, text, opts \\ []) do
    min_term_freq = Keyword.get(opts, :min_term_freq, 1)
    min_doc_freq = Keyword.get(opts, :min_doc_freq, 1)

    query = %{
      query: %{
        bool: %{
          must: [
            %{
              more_like_this: %{
                fields: ["text"],
                like: text,
                min_term_freq: min_term_freq,
                min_doc_freq: min_doc_freq
              }
            }
          ],
          filter: [
            %{term: %{speech_id: to_string(speech_id)}}
          ]
        }
      }
    }

    search(@questions_index, query)
  end

  # =========================================================================
  # Domain Functions: Transcript Segments & Slides (Card 295.5)
  # =========================================================================

  @doc """
  Public function to index a transcript segment.
  """
  def index_transcript_segment(segment, opts \\ []) do
    doc = normalize_map(segment)
    id = doc[:segment_id] || doc["segment_id"] || doc[:id] || doc["id"]

    if is_nil(id) or id == "" do
      {:error, :missing_id}
    else
      index = Keyword.get(opts, :index, @transcripts_index)
      index_document(index, to_string(id), doc, opts)
    end
  end

  @doc """
  Public function to index a slide.
  """
  def index_slide(slide, opts \\ []) do
    doc = normalize_map(slide)
    speech_id = doc[:speech_id] || doc["speech_id"]
    slide_num = doc[:slide_number] || doc["slide_number"]

    cond do
      is_nil(speech_id) or speech_id == "" ->
        {:error, :missing_speech_id}

      is_nil(slide_num) or slide_num == "" ->
        {:error, :missing_slide_number}

      true ->
        index = Keyword.get(opts, :index, @slides_index)
        id = "#{speech_id}_#{slide_num}"
        index_document(index, id, doc, opts)
    end
  end

  @doc """
  Matches question text against transcript segments for the speech.
  Used to identify relevant speech context (Card 304).
  """
  def match_transcript_context(speech_id, text) do
    query = %{
      query: %{
        bool: %{
          must: [
            %{match: %{text: text}}
          ],
          filter: [
            %{term: %{speech_id: to_string(speech_id)}}
          ]
        }
      }
    }

    search(@transcripts_index, query)
  end

  # =========================================================================
  # Domain Functions: Notes
  # =========================================================================

  @doc """
  Indexes a user note taken during a speech.
  Accepts either a map with string/atom keys or a struct.
  """
  def index_note(note, opts \\ []) do
    doc = normalize_note(note)
    id = doc[:id] || doc["id"]

    if is_nil(id) or id == "" do
      {:error, :missing_id}
    else
      index = Keyword.get(opts, :index, @notes_index)
      index_document(index, to_string(id), doc, opts)
    end
  end

  @doc """
  Removes a note from the index.
  """
  def delete_note(note_id, opts \\ []) do
    if is_nil(note_id) or note_id == "" do
      {:error, :missing_id}
    else
      index = Keyword.get(opts, :index, @notes_index)
      delete_document(index, to_string(note_id), opts)
    end
  end

  @doc """
  Searches notes for a specific user within a speech.
  """
  def search_notes(speech_id, user_id, query_text, opts \\ []) do
    index = Keyword.get(opts, :index, @notes_index)

    query = %{
      query: %{
        bool: %{
          must: [
            %{match: %{body: query_text}}
          ],
          filter: [
            %{term: %{speech_id: to_string(speech_id)}},
            %{term: %{user_id: to_string(user_id)}}
          ]
        }
      }
    }

    search(index, query)
  end

  @doc """
  Searches all notes within a speech (e.g. for aggregations or post-speech summary).
  """
  def search_speech_notes(speech_id, query_text, opts \\ []) do
    index = Keyword.get(opts, :index, @notes_index)

    query = %{
      query: %{
        bool: %{
          must: [
            %{match: %{body: query_text}}
          ],
          filter: [
            %{term: %{speech_id: to_string(speech_id)}}
          ]
        }
      }
    }

    search(index, query)
  end

  # =========================================================================
  # Helpers
  # =========================================================================

  defp normalize_note(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> normalize_note()
  end

  defp normalize_note(map) when is_map(map) do
    now = DateTime.utc_now()

    %{
      id: map[:id] || map["id"],
      speech_id: to_string(map[:speech_id] || map["speech_id"]),
      user_id: to_string(map[:user_id] || map["user_id"]),
      body: map[:body] || map["body"] || map[:text] || map["text"],
      offset_ms: map[:offset_ms] || map["offset_ms"] || 0,
      slide_number: map[:slide_number] || map["slide_number"],
      inserted_at: map[:inserted_at] || map["inserted_at"] || now,
      updated_at: map[:updated_at] || map["updated_at"] || now
    }
  end

  defp normalize_question(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> normalize_question()
  end

  defp normalize_question(map) when is_map(map) do
    %{
      id: map[:id] || map["id"],
      speech_id: to_string(map[:speech_id] || map["speech_id"]),
      user_id: to_string(map[:user_id] || map["user_id"]),
      text: map[:text] || map["text"],
      offset_ms: map[:offset_ms] || map["offset_ms"] || 0,
      slide_number: map[:slide_number] || map["slide_number"],
      tag: map[:tag] || map["tag"],
      inserted_at: map[:inserted_at] || map["inserted_at"] || DateTime.utc_now()
    }
  end

  defp normalize_map(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  defp normalize_map(map) when is_map(map), do: map
end
