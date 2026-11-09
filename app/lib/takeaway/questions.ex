defmodule Takeaway.Questions do
  @moduledoc "Questions asked by users during a speech."
  import Ecto.Query
  alias Takeaway.Questions.Question
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
