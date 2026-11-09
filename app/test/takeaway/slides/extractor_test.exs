defmodule Takeaway.Slides.ExtractorTest do
  use ExUnit.Case, async: true

  alias Takeaway.SlideFixtures
  alias Takeaway.Slides.{Extractor, Pdf, Pptx}

  @moduletag :tmp_dir

  # The PDF tests need poppler's pdftotext (Debian: apt-get install poppler-utils).
  @pdf_skip if Pdf.available?(),
              do: false,
              else: "pdftotext not installed (apt-get install poppler-utils)"

  describe "clean_text/1 and Pdf.split_pages/1" do
    test "normalizes whitespace and drops blank lines" do
      assert Extractor.clean_text("  Hello   world \r\n\n\t Two  lines  ") ==
               "Hello world\nTwo lines"

      assert Extractor.clean_text(<<"ok ", 0xFF>>) == "ok �"
    end

    test "splits pdftotext output on form feeds, keeping empty pages" do
      assert Pdf.split_pages("one\n\fpage two\n\f\f") == ["one", "page two", ""]
      assert Pdf.split_pages("") == []
    end
  end

  describe "pdf" do
    @describetag skip: @pdf_skip

    test "a 10-page text PDF yields 10 texts in page order", %{tmp_dir: dir} do
      path = Path.join(dir, "deck.pdf")
      File.write!(path, SlideFixtures.pdf(Enum.map(1..10, &"Slide number #{&1}")))

      assert {:ok, texts} = Extractor.Default.extract(path, [])
      assert length(texts) == 10
      assert Enum.at(texts, 0) == "Slide number 1"
      assert Enum.at(texts, 9) == "Slide number 10"
    end

    test "a page without text comes back empty", %{tmp_dir: dir} do
      path = Path.join(dir, "scan.pdf")
      File.write!(path, SlideFixtures.pdf(["Title", nil, "End"]))
      assert {:ok, ["Title", "", "End"]} = Pdf.extract(path)
    end

    test "max_pages caps the pages read", %{tmp_dir: dir} do
      path = Path.join(dir, "long.pdf")
      File.write!(path, SlideFixtures.pdf(Enum.map(1..5, &"P#{&1}")))
      assert {:ok, ["P1", "P2"]} = Pdf.extract(path, max_pages: 2)
    end

    test "a corrupt PDF is an error, not a crash", %{tmp_dir: dir} do
      path = Path.join(dir, "bad.pdf")
      File.write!(path, "%PDF-1.4 this is not really a pdf")
      assert {:error, _} = Pdf.extract(path)
    end
  end

  test "a missing PDF is :enoent", %{tmp_dir: dir} do
    assert {:error, :enoent} = Pdf.extract(Path.join(dir, "nope.pdf"))
  end

  describe "pptx" do
    test "reads slide text in presentation order", %{tmp_dir: dir} do
      path = Path.join(dir, "deck.pptx")

      bin =
        SlideFixtures.pptx(
          [
            SlideFixtures.slide_xml([["Second ", "slide"], ["R&amp;D &lt;3 &#233;t&#xE9;"]]),
            SlideFixtures.slide_xml([["First"]]),
            SlideFixtures.slide_xml([])
          ],
          [2, 1, 3]
        )

      File.write!(path, bin)

      assert {:ok, ["First", "Second slide\nR&D <3 été", ""]} =
               Extractor.Default.extract(path, [])

      assert {:ok, ["First"]} = Pptx.extract(path, max_pages: 1)
    end

    test "an oversized slide part is skipped instead of inflated", %{tmp_dir: dir} do
      path = Path.join(dir, "bomb.pptx")
      huge = SlideFixtures.slide_xml([[String.duplicate("a", 6_000_000)]])
      File.write!(path, SlideFixtures.pptx([SlideFixtures.slide_xml([["ok"]]), huge]))

      assert {:ok, ["ok", ""]} = Pptx.extract(path)
    end

    test "a file that isn't a pptx zip is an error", %{tmp_dir: dir} do
      path = Path.join(dir, "fake.pptx")
      File.write!(path, "not a zip")
      assert {:error, :not_a_pptx} = Pptx.extract(path)
      assert {:error, :enoent} = Pptx.extract(Path.join(dir, "nope.pptx"))
    end
  end

  test "legacy .ppt and other formats are unsupported", %{tmp_dir: dir} do
    path = Path.join(dir, "old.ppt")
    File.write!(path, "binary")
    assert {:error, :unsupported_format} = Extractor.Default.extract(path, [])
  end
end
