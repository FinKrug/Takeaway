defmodule Takeaway.SlidesTest do
  # Mutates application env, so not async.
  use Takeaway.DataCase, async: false

  import ExUnit.CaptureLog

  alias Takeaway.{Accounts, Events, SlideFixtures, Slides, SpeechCreator, Speeches}
  alias Takeaway.Slides.Pdf

  setup do
    {:ok, event} = Events.create_event(%{name: "Conf"})
    {:ok, speaker} = Accounts.create_speaker(%{name: "Sam"})

    {:ok, speech} =
      Speeches.create_speech(%{title: "Talk", event_id: event.id, speaker_id: speaker.id})

    Application.put_env(:takeaway, :indexer, Takeaway.FakeIndexer)
    Application.put_env(:takeaway, :indexer_test_pid, self())

    on_exit(fn ->
      for key <- [
            :indexer,
            :indexer_test_pid,
            :indexer_fail_slide_2,
            :slide_extractor,
            :extractor_test_pid,
            :extract_slides
          ],
          do: Application.delete_env(:takeaway, key)
    end)

    %{speech: speech}
  end

  describe "storage" do
    test "upsert stores slides by number and re-processing doesn't duplicate", %{speech: speech} do
      assert {:ok, [s1, s2, s3]} = Slides.upsert_slides(speech.id, ["a", "", "c"])
      assert {s1.slide_number, s2.slide_number, s3.slide_number} == {1, 2, 3}
      assert s2.text == ""

      # Same deck again, then a shorter one: rows are updated, leftovers removed.
      assert {:ok, _} = Slides.upsert_slides(speech.id, ["a", "", "c"])
      assert {:ok, _} = Slides.upsert_slides(speech.id, ["A2", "B2"])

      assert [%{slide_number: 1, text: "A2"}, %{slide_number: 2, text: "B2"}] =
               Slides.list_slides(speech.id)

      assert %{text: "B2"} = Slides.get_slide(speech.id, 2)
    end

    test "very long text is capped", %{speech: speech} do
      assert {:ok, [slide]} = Slides.upsert_slides(speech.id, [String.duplicate("x", 30_000)])
      assert String.length(slide.text) == 20_000
    end

    test "slides are deleted with their speech", %{speech: speech} do
      {:ok, _} = Slides.upsert_slides(speech.id, ["a"])
      Repo.delete!(speech)
      assert Slides.list_slides(speech.id) == []
    end

    test "the changeset ignores speech_id in attrs", %{speech: speech} do
      changeset =
        Slides.Slide.changeset(%Slides.Slide{}, %{
          speech_id: speech.id,
          slide_number: 1,
          text: "a"
        })

      refute changeset.valid?
      assert %{speech_id: ["can't be blank"]} = errors_on(changeset)

      assert {:ok, slide} =
               %Slides.Slide{speech_id: speech.id}
               |> Slides.Slide.changeset(%{speech_id: speech.id + 1, slide_number: 1, text: "a"})
               |> Repo.insert()

      assert slide.speech_id == speech.id
    end

    test "title is the first non-blank line" do
      assert Slides.title("Agenda\nmore") == "Agenda"
      assert Slides.title("") == ""
    end
  end

  describe "process_artifact/1" do
    setup %{speech: speech} do
      Application.put_env(:takeaway, :slide_extractor, Takeaway.FakeSlideExtractor)
      artifact = fn url -> artifact(speech, url) end
      %{artifact: artifact}
    end

    test "stores and indexes each slide once", %{speech: speech, artifact: artifact} do
      assert {:ok, slides} = Slides.process_artifact(artifact.("deck.pdf"))
      assert Enum.map(slides, & &1.slide_number) == [1, 2, 3]

      speech_id = to_string(speech.id)

      assert_received {:indexed_slide,
                       %{speech_id: ^speech_id, slide_number: 1, title: "Intro", content: _}}

      assert_received {:indexed_slide, %{slide_number: 2, title: "", content: ""}}
      assert_received {:indexed_slide, %{slide_number: 3, title: "Thanks"}}
      refute_received {:indexed_slide, _}
    end

    test "an indexing failure keeps the stored slides", %{speech: speech, artifact: artifact} do
      Application.put_env(:takeaway, :indexer_fail_slide_2, true)

      log =
        capture_log(fn -> assert {:ok, _} = Slides.process_artifact(artifact.("deck.pdf")) end)

      assert log =~ "indexing failed for 1 of 3 slides"
      assert length(Slides.list_slides(speech.id)) == 3
    end

    test "a missing file or a crashing extractor is logged, not raised", %{artifact: artifact} do
      log =
        capture_log(fn ->
          assert {:error, :enoent} = Slides.process_artifact(artifact.("missing.pdf"))
          assert {:error, {:exception, "boom"}} = Slides.process_artifact(artifact.("boom.pdf"))
        end)

      assert log =~ "extraction of artifact"
      assert log =~ ":enoent"
    end

    test "unsupported formats are skipped", %{speech: speech} do
      Application.delete_env(:takeaway, :slide_extractor)

      assert {:error, :unsupported_format} =
               Slides.process_artifact(artifact(speech, "deck.ppt"))

      assert Slides.list_slides(speech.id) == []
    end
  end

  describe "on upload" do
    test "speech creation returns at once and extraction runs in the background", %{
      speech: speech
    } do
      Application.put_env(:takeaway, :extract_slides, true)
      Application.put_env(:takeaway, :slide_extractor, Takeaway.FakeSlideExtractor)
      Application.put_env(:takeaway, :extractor_test_pid, self())

      path = Path.join(System.tmp_dir!(), "deck-#{System.unique_integer([:positive])}.pdf")
      File.write!(path, "%PDF")
      on_exit(fn -> File.rm(path) end)

      assert {:ok, created} =
               SpeechCreator.create_speech(%{title: "Deck talk", speaker_id: speech.speaker_id}, [
                 {"slides", "deck.pdf", path}
               ])

      assert_receive {:extract_called, stored_path}, 5_000
      assert stored_path =~ "#{created.id}-slides-"

      for _ <- 1..3, do: assert_receive({:indexed_slide, _}, 5_000)
      assert length(Slides.list_slides(created.id)) == 3
    end

    test "extraction is off when disabled", %{speech: speech} do
      Application.put_env(:takeaway, :extract_slides, false)
      assert :ignore = Slides.extract_async(artifact(speech, "deck.pdf"))
      assert :ignore = Slides.extract_async(%Speeches.Artifact{kind: "plan"})
    end
  end

  describe "real PDF" do
    @describetag skip:
                   if(Pdf.available?(),
                     do: false,
                     else: "pdftotext not installed (apt-get install poppler-utils)"
                   )

    test "a 10-page PDF upload ends up as 10 slides", %{speech: speech} do
      Application.put_env(:takeaway, :extract_slides, true)

      path = Path.join(System.tmp_dir!(), "real-#{System.unique_integer([:positive])}.pdf")
      File.write!(path, SlideFixtures.pdf(Enum.map(1..10, &"Page #{&1}")))
      on_exit(fn -> File.rm(path) end)

      assert {:ok, created} =
               SpeechCreator.create_speech(%{title: "PDF talk", speaker_id: speech.speaker_id}, [
                 {"slides", "deck.pdf", path}
               ])

      for _ <- 1..10, do: assert_receive({:indexed_slide, _}, 10_000)

      slides = Slides.list_slides(created.id)
      assert Enum.map(slides, & &1.slide_number) == Enum.to_list(1..10)
      assert List.last(slides).text == "Page 10"
    end
  end

  describe "current slide" do
    test "count_slides/1 counts the stored slides", %{speech: speech} do
      assert Slides.count_slides(speech.id) == 0
      {:ok, _} = Slides.upsert_slides(speech.id, ["a", "b", "c"])
      assert Slides.count_slides(speech.id) == 3
    end

    test "current_slide/2 defaults to 1 with a deck and caps at its size", %{speech: speech} do
      assert SpeechCreator.current_slide(speech, 0) == nil
      assert SpeechCreator.current_slide(speech, 5) == 1
      assert SpeechCreator.current_slide(%{speech | current_slide: 7}, 0) == 7
      assert SpeechCreator.current_slide(%{speech | current_slide: 7}, 5) == 5
    end

    test "set_current_slide/3 clamps, persists and broadcasts on the speech topic",
         %{speech: speech} do
      SpeechCreator.subscribe(speech.id)
      id = speech.id

      assert {:ok, %{current_slide: 2} = speech} = SpeechCreator.set_current_slide(speech, 2, 3)
      assert_receive {:slide_changed, ^id, 2}
      assert Speeches.get_speech!(id).current_slide == 2

      assert {:ok, %{current_slide: 3} = speech} = SpeechCreator.set_current_slide(speech, 9, 3)
      assert_receive {:slide_changed, ^id, 3}

      # already there: no write, no broadcast
      assert {:ok, %{current_slide: 3} = speech} = SpeechCreator.set_current_slide(speech, 4, 3)
      refute_receive {:slide_changed, _, _}, 50

      assert {:ok, %{current_slide: 1} = speech} = SpeechCreator.set_current_slide(speech, -2, 3)
      assert_receive {:slide_changed, ^id, 1}

      # without a deck only the lower bound applies
      assert {:ok, %{current_slide: 42} = speech} = SpeechCreator.set_current_slide(speech, 42, 0)
      assert Speeches.get_speech!(id).current_slide == 42

      # ...up to a sane maximum, so huge values can't overflow the column
      max = SpeechCreator.max_slide()

      assert {:ok, %{current_slide: ^max}} =
               SpeechCreator.set_current_slide(speech, 10_000_000_000_000, 0)

      assert Speeches.get_speech!(id).current_slide == max
    end
  end

  defp artifact(speech, url) do
    {:ok, a} =
      Speeches.create_artifact(%{speech_id: speech.id, kind: "slides", title: url, url: url})

    a
  end
end
