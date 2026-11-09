defmodule Takeaway.Questions.Grouping do
  @moduledoc """
  Best-effort, speech-scoped grouping. Elasticsearch supplies candidates; Postgres
  owns memberships. A speech row lock serializes assignment across app replicas.
  Search failure leaves a singleton. Counts always exclude retracted questions.
  """
  import Ecto.Query
  require Logger
  alias Takeaway.{Elasticsearch, Questions, Repo}
  alias Takeaway.Questions.{Group, Question}
  alias Takeaway.Speeches.Speech

  @stop_words ~w(a an the is are was were do does did how what why when where who
                can could would should will you we i it this that to of in on for
                and or with your our please explain tell me)
  @threshold 0.6

  @doc "Jaccard similarity of content words; generic one-word questions stay separate."
  def similarity(left, right) do
    a = tokens(left)
    b = tokens(right)

    if MapSet.size(a) < 2 or MapSet.size(b) < 2 do
      0.0
    else
      MapSet.size(MapSet.intersection(a, b)) / MapSet.size(MapSet.union(a, b))
    end
  end

  defp tokens(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.reject(&(&1 in @stop_words))
    |> MapSet.new()
  end

  @doc "Assign once, even when multiple replicas receive the same PubSub event."
  def assign(%Question{} = question) do
    candidates = search_candidates(question)

    result =
      Repo.transaction(fn ->
        Repo.one!(from s in Speech, where: s.id == ^question.speech_id, lock: "FOR UPDATE")
        current = Repo.get!(Question, question.id)

        cond do
          current.retracted_at != nil -> current
          current.group_id != nil -> current
          true -> assign_locked(current, candidates)
        end
      end)

    case result do
      {:ok, updated} ->
        notify(updated.speech_id)
        {:ok, updated}

      error ->
        error
    end
  end

  defp search_candidates(question) do
    case Elasticsearch.more_like_this_question(question.speech_id, question.text) do
      {:ok, %{"hits" => hits}} ->
        {:ok, Enum.flat_map(hits, &hit_id/1)}

      {:error, reason} ->
        Logger.warning("Question grouping search unavailable: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.warning("Question grouping search failed: #{Exception.message(error)}")
      {:error, :search_failed}
  end

  defp hit_id(%{"_id" => id}) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> [id]
      _ -> []
    end
  end

  defp hit_id(_), do: []

  @doc "Finish pending assignments before caching a post-speech summary."
  def assign_pending(speech_id) do
    Repo.all(
      from q in Question,
        where: q.speech_id == ^speech_id and is_nil(q.retracted_at) and is_nil(q.group_id),
        order_by: [asc: q.id]
    )
    |> Enum.each(&assign/1)
  end

  defp assign_locked(question, candidates) do
    match = best_match(question, candidates)

    group =
      case match do
        %Question{group_id: id} when not is_nil(id) ->
          # Validate the group as well as the search hit against this speech.
          Repo.get_by(Group, id: id, speech_id: question.speech_id)

        _ ->
          nil
      end

    group = group || Repo.insert!(%Group{speech_id: question.speech_id, text: question.text})

    # A matching, not-yet-processed question can join atomically with this one.
    if match && is_nil(match.group_id) do
      match |> Ecto.Changeset.change(group_id: group.id) |> Repo.update!()
    end

    updated = question |> Ecto.Changeset.change(group_id: group.id) |> Repo.update!()

    Logger.debug(
      "Question grouping: #{if match, do: "hit", else: "new"} speech=#{question.speech_id} group=#{group.id}"
    )

    updated
  end

  defp best_match(_question, {:error, _}), do: nil

  defp best_match(question, {:ok, ids}) do
    # Include recent DB rows to bridge ES's refresh interval and simultaneous
    # submissions. All candidates are checked against the source of truth.
    recent =
      Repo.all(
        from q in Question,
          where: q.speech_id == ^question.speech_id and is_nil(q.retracted_at),
          order_by: [desc: q.id],
          limit: 100,
          select: q.id
      )

    ids = Enum.uniq(ids ++ recent)
    threshold = Application.get_env(:takeaway, :question_group_similarity, @threshold)

    Repo.all(
      from q in Question,
        where:
          q.id in ^ids and q.id != ^question.id and
            q.speech_id == ^question.speech_id and is_nil(q.retracted_at),
        order_by: [asc: q.id]
    )
    |> Enum.map(&{&1, similarity(question.text, &1.text)})
    |> Enum.filter(fn {_, score} -> score >= threshold end)
    |> Enum.max_by(fn {_, score} -> score end, fn -> nil end)
    |> case do
      nil -> nil
      {match, _} -> match
    end
  end

  @doc "Removes empty groups, and replaces the representative when it was retracted."
  def retract(%Question{} = question) do
    result =
      Repo.transaction(fn ->
        Repo.one!(from s in Speech, where: s.id == ^question.speech_id, lock: "FOR UPDATE")
        current = Repo.get!(Question, question.id)

        if current.retracted_at && current.group_id do
          group = Repo.get_by(Group, id: current.group_id, speech_id: current.speech_id)

          first =
            Repo.one(
              from q in Question,
                where:
                  q.speech_id == ^current.speech_id and q.group_id == ^current.group_id and
                    is_nil(q.retracted_at),
                order_by: [asc: q.id],
                limit: 1
            )

          cond do
            is_nil(group) ->
              :ok

            first ->
              group |> Ecto.Changeset.change(text: first.text) |> Repo.update!()

            true ->
              Repo.update_all(
                from(q in Question,
                  where: q.speech_id == ^current.speech_id and q.group_id == ^group.id
                ),
                set: [group_id: nil]
              )

              Repo.delete!(group)
          end
        end
      end)

    notify(question.speech_id)
    result
  end

  defp notify(speech_id) do
    Phoenix.PubSub.broadcast(
      Takeaway.PubSub,
      Questions.topic(speech_id),
      {:question_groups_updated, speech_id}
    )
  end
end
