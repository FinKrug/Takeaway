defmodule Takeaway.Speeches do
  @moduledoc "Speeches, their artifacts and live transcript segments."
  import Ecto.Query
  alias Takeaway.Repo
  alias Takeaway.Speeches.{Artifact, Speech, TranscriptSegment}

  def list_speeches(event_id) do
    Repo.all(from s in Speech, where: s.event_id == ^event_id, order_by: [asc: s.id])
  end

  def get_speech(id), do: Repo.get(Speech, id)
  def get_speech!(id), do: Repo.get!(Speech, id)
  def get_speech_by_join_code(code), do: Repo.get_by(Speech, join_code: String.upcase(code))

  def create_speech(attrs), do: %Speech{} |> Speech.changeset(attrs) |> Repo.insert()

  def update_speech(%Speech{} = speech, attrs),
    do: speech |> Speech.changeset(attrs) |> Repo.update()

  def start_speech(%Speech{} = speech, now \\ now()),
    do: update_speech(speech, %{started_at: now})

  def end_speech(%Speech{} = speech, now \\ now()),
    do: update_speech(speech, %{ended_at: now})

  def create_artifact(attrs), do: %Artifact{} |> Artifact.changeset(attrs) |> Repo.insert()

  def list_artifacts(speech_id, kind \\ nil) do
    query = from a in Artifact, where: a.speech_id == ^speech_id, order_by: [asc: a.id]
    query = if kind, do: where(query, [a], a.kind == ^kind), else: query
    Repo.all(query)
  end

  def get_artifact(id), do: Repo.get(Artifact, id)
  def get_artifact!(id), do: Repo.get!(Artifact, id)

  def add_transcript_segment(attrs),
    do: %TranscriptSegment{} |> TranscriptSegment.changeset(attrs) |> Repo.insert()

  def list_transcript_segments(artifact_id) do
    Repo.all(
      from t in TranscriptSegment,
        where: t.artifact_id == ^artifact_id,
        order_by: [asc: t.start_ms, asc: t.id]
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
