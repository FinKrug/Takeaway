defmodule Takeaway.Slides.Extractor do
  @moduledoc """
  Turns a slide deck file into one text string per slide, in slide order
  (element 0 is slide 1). An image-only slide yields `""`.

  The implementation is configured with `config :takeaway, :slide_extractor,
  MyModule` (default: `Takeaway.Slides.Extractor.Default`), so tests can run
  without poppler.

  Options: `:max_pages` (default 300) caps how many slides are read.
  """
  @callback extract(path :: Path.t(), opts :: keyword()) ::
              {:ok, [String.t()]} | {:error, term()}

  def extract(path, opts \\ []), do: impl().extract(path, opts)

  def impl,
    do: Application.get_env(:takeaway, :slide_extractor, Takeaway.Slides.Extractor.Default)

  @doc """
  Normalizes extracted text: valid UTF-8, runs of spaces collapsed, lines
  trimmed, blank lines dropped.
  """
  def clean_text(text) do
    text
    |> String.replace_invalid()
    |> String.split(["\r\n", "\n", "\r"])
    |> Enum.map(&(&1 |> String.replace(~r/[ \t\x{00A0}]+/u, " ") |> String.trim()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end
end

defmodule Takeaway.Slides.Extractor.Default do
  @moduledoc """
  Picks the extractor from the file extension: `.pdf` uses poppler's
  `pdftotext` (`Takeaway.Slides.Pdf`), `.pptx` reads the slide XML from the zip
  (`Takeaway.Slides.Pptx`). Anything else, including legacy `.ppt`, returns
  `{:error, :unsupported_format}`.
  """
  @behaviour Takeaway.Slides.Extractor

  @impl true
  def extract(path, opts) do
    case path |> Path.extname() |> String.downcase() do
      ".pdf" -> Takeaway.Slides.Pdf.extract(path, opts)
      ".pptx" -> Takeaway.Slides.Pptx.extract(path, opts)
      _ -> {:error, :unsupported_format}
    end
  end
end
