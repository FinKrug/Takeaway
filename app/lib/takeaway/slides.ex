defmodule Takeaway.Slides do
  @moduledoc """
  Per-slide text of a speech's slide deck.

  When `Takeaway.SpeechCreator` saves a slides artifact it calls
  `extract_async/1`: a task under `Takeaway.Slides.TaskSupervisor` extracts the
  text of every page (`Takeaway.Slides.Extractor`), upserts one `slides` row per
  page (numbered from 1) and hands each slide to `Takeaway.Indexer.index_slide/1`.
  Extractions run one at a time per pod to stay inside the pod's memory limit.
  Failures are logged and traced, never raised to the caller.

  Set `config :takeaway, :extract_slides, false` to skip extraction (tests do).
  """
  import Ecto.Query
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Takeaway.{Indexer, Repo, SpeechCreator}
  alias Takeaway.Slides.{Extractor, Slide}
  alias Takeaway.Speeches.Artifact

  # Characters kept per slide in the database, and sent to the search index.
  @max_text 20_000
  @max_index_text 8_000
  @max_title 200

  @doc "Slides of a speech, ordered by slide number."
  def list_slides(speech_id) do
    Repo.all(from s in Slide, where: s.speech_id == ^speech_id, order_by: [asc: s.slide_number])
  end

  def get_slide(speech_id, slide_number),
    do: Repo.get_by(Slide, speech_id: speech_id, slide_number: slide_number)

  @doc """
  Stores `texts` as slides 1..n of the speech. Existing rows are updated in
  place (unique on speech + number), and slides numbered above n, left over
  from an earlier, longer deck, are deleted. Returns `{:ok, slides}`.
  """
  def upsert_slides(speech_id, texts) when is_list(texts) do
    now = DateTime.utc_now(:second)

    rows =
      texts
      |> Enum.with_index(1)
      |> Enum.map(fn {text, n} ->
        %{
          speech_id: speech_id,
          slide_number: n,
          text: String.slice(text || "", 0, @max_text),
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.transaction(fn ->
      for chunk <- Enum.chunk_every(rows, 1_000) do
        Repo.insert_all(Slide, chunk,
          on_conflict: {:replace, [:text, :updated_at]},
          conflict_target: [:speech_id, :slide_number]
        )
      end

      Repo.delete_all(
        from s in Slide, where: s.speech_id == ^speech_id and s.slide_number > ^length(rows)
      )

      list_slides(speech_id)
    end)
  end

  @doc """
  Sends each slide to `Takeaway.Indexer.index_slide/1`. Failures are logged and
  counted; the stored slides are not touched. Returns `{indexed, failed}`.
  """
  def index_slides(slides) do
    results = Enum.map(slides, &index_slide/1)
    failed = Enum.reject(results, &(&1 == :ok))

    if failed != [] do
      Logger.warning(
        "[Slides] indexing failed for #{length(failed)} of #{length(slides)} slides: #{inspect(hd(failed))}"
      )
    end

    {length(results) - length(failed), length(failed)}
  end

  defp index_slide(%Slide{} = slide) do
    Indexer.index_slide(%{
      speech_id: to_string(slide.speech_id),
      slide_number: slide.slide_number,
      title: title(slide.text),
      content: String.slice(slide.text, 0, @max_index_text)
    })
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "First non-blank line of the slide text, used as its title."
  def title(text) do
    text
    |> String.split("\n", trim: true)
    |> List.first("")
    |> String.slice(0, @max_title)
  end

  @doc """
  Starts extraction of a slides artifact in the background. Returns
  `{:ok, pid}`, or `:ignore` for other artifacts or when extraction is off.
  """
  def extract_async(%Artifact{kind: "slides"} = artifact) do
    if Application.get_env(:takeaway, :extract_slides, true) do
      ctx = OpenTelemetry.Ctx.get_current()

      Task.Supervisor.start_child(Takeaway.Slides.TaskSupervisor, fn ->
        OpenTelemetry.Ctx.attach(ctx)
        # One extraction at a time on this node; others wait for the lock.
        :global.trans({__MODULE__, self()}, fn -> process_artifact(artifact) end, [node()])
      end)
    else
      :ignore
    end
  end

  def extract_async(_artifact), do: :ignore

  @doc """
  Extracts, stores and indexes the text of a slides artifact, synchronously.
  Returns `{:ok, slides}` or `{:error, reason}`; never raises.
  """
  def process_artifact(%Artifact{} = artifact, opts \\ []) do
    # `url` is the stored file name in the uploads dir.
    path = Path.join(SpeechCreator.uploads_dir(), Path.basename(artifact.url || ""))

    Tracer.with_span "slides.extract", %{
      attributes: %{"speech.id" => artifact.speech_id, "artifact.id" => artifact.id}
    } do
      result =
        try do
          do_process(artifact, path, opts)
        rescue
          e -> {:error, {:exception, Exception.message(e)}}
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      report(artifact, result)
      result
    end
  end

  defp do_process(artifact, path, opts) do
    with {:ok, texts} <- Extractor.extract(path, opts),
         {:ok, slides} <- upsert_slides(artifact.speech_id, texts) do
      {indexed, failed} = index_slides(slides)

      Tracer.set_attributes(%{
        "slides.count" => length(slides),
        "slides.indexed" => indexed,
        "slides.index_failed" => failed,
        "slides.empty" => Enum.count(slides, &(&1.text == ""))
      })

      {:ok, slides}
    end
  end

  defp report(artifact, {:ok, slides}) do
    Logger.info("[Slides] speech #{artifact.speech_id}: stored text of #{length(slides)} slides")
  end

  defp report(artifact, {:error, :unsupported_format}) do
    Tracer.set_attributes(%{"slides.skipped" => "unsupported_format"})

    Logger.info(
      "[Slides] speech #{artifact.speech_id}: skipped #{inspect(artifact.title)} (unsupported format)"
    )
  end

  defp report(artifact, {:error, reason}) do
    Tracer.set_status(OpenTelemetry.status(:error, inspect(reason)))

    Logger.warning(
      "[Slides] speech #{artifact.speech_id}: extraction of artifact #{artifact.id} failed: #{inspect(reason)}"
    )
  end
end
