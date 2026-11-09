defmodule Takeaway.Questions do
  @moduledoc "Questions asked by users during a speech."
  import Ecto.Query
  alias Takeaway.Accounts.User
  alias Takeaway.Questions.Question
  alias Takeaway.Speeches.Speech
  alias Takeaway.Repo

  @doc "Lists a speech's questions in speech order. Retracted ones are excluded unless `include_retracted: true`."
  def list_questions(speech_id, opts \\ []) do
    query =
      from q in Question,
        where: q.speech_id == ^speech_id,
        order_by: [asc: q.offset_ms, asc: q.id]

    if Keyword.get(opts, :include_retracted, false),
      do: Repo.all(query),
      else: Repo.all(where(query, [q], is_nil(q.retracted_at)))
  end

  @doc "PubSub topic for a speech's question events."
  def topic(speech_id), do: "speech:#{speech_id}"

  def subscribe(speech_id), do: Phoenix.PubSub.subscribe(Takeaway.PubSub, topic(speech_id))

  @doc """
  Submits a question from `user` to `speech`, stamped with the offset from the speech start
  (0 if not started). Runs the filter hook first (see `filter_text/1`); on success broadcasts
  `{:question_created, question}` on `speech:<id>`.
  """
  def submit_question(%Speech{} = speech, %User{} = user, attrs, now \\ DateTime.utc_now()) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    text = attrs["text"] |> to_string() |> String.trim()

    with {:ok, text} <- filter_text(text),
         {:ok, question} <-
           create_question(%{
             "text" => text,
             "slide_number" => attrs["slide_number"],
             "offset_ms" => offset_ms(speech, now),
             "user_id" => user.id,
             "speech_id" => speech.id
           }) do
      broadcast(speech.id, {:question_created, question})
      {:ok, question}
    end
  end

  @doc """
  Retracts a question, only if `user` asked it. Broadcasts `{:question_retracted, question}`.
  Returns `{:error, :not_found}` or `{:error, :forbidden}`.
  """
  def retract_question_by(question_id, %User{} = user) do
    case get_question(question_id) do
      nil ->
        {:error, :not_found}

      %Question{user_id: uid} when uid != user.id ->
        {:error, :forbidden}

      %Question{retracted_at: at} = q when not is_nil(at) ->
        {:ok, q}

      question ->
        with {:ok, question} <- retract_question(question) do
          broadcast(question.speech_id, {:question_retracted, question})
          {:ok, question}
        end
    end
  end

  @doc """
  Filter hook run before saving. Configure `config :takeaway, :question_filter` with a
  1-arity function or `{module, function}` returning `{:ok, text}` or `{:error, reason}`.
  Defaults to accepting the text unchanged.
  """
  def filter_text(text) do
    case Application.get_env(:takeaway, :question_filter) do
      nil -> {:ok, text}
      fun when is_function(fun, 1) -> fun.(text)
      {m, f} -> apply(m, f, [text])
    end
  end

  @question_starters ~w(who what when where why how which whose whom is are am was were do does did
                        can could will would shall should may might have has had isn't aren't
                        don't doesn't didn't can't won't wouldn't shouldn't)

  @doc """
  Heuristic: does `text` look like an audience question? True when the text passes
  `filter_text/1` and either ends with `?` or starts with an interrogative word.
  """
  def question?(text) when is_binary(text) do
    text = String.trim(text)

    text != "" and match?({:ok, _}, filter_text(text)) and
      (String.ends_with?(text, "?") or starts_with_interrogative?(text))
  end

  def question?(_), do: false

  defp starts_with_interrogative?(text) do
    case text |> String.downcase() |> String.split(~r/[\s,]+/, parts: 2) do
      [first, _rest] -> first in @question_starters
      _ -> false
    end
  end

  defp offset_ms(%Speech{started_at: nil}, _now), do: 0

  defp offset_ms(%Speech{started_at: started}, now),
    do: max(DateTime.diff(now, started, :millisecond), 0)

  defp broadcast(speech_id, msg),
    do: Phoenix.PubSub.broadcast(Takeaway.PubSub, topic(speech_id), msg)

  def get_question(id), do: Repo.get(Question, id)
  def get_question!(id), do: Repo.get!(Question, id)

  def create_question(attrs), do: %Question{} |> Question.changeset(attrs) |> Repo.insert()

  def retract_question(%Question{} = question, now \\ now()) do
    question |> Ecto.Changeset.change(retracted_at: now) |> Repo.update()
  end

  def assign_group(%Question{} = question, group_id) do
    question |> Ecto.Changeset.change(group_id: group_id) |> Repo.update()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
