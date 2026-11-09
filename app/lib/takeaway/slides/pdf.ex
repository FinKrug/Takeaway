defmodule Takeaway.Slides.Pdf do
  @moduledoc """
  Embedded-text extraction from PDF slides with poppler's `pdftotext`
  (Debian package `poppler-utils`). One `pdftotext` run reads the whole deck and
  separates pages with form feeds, so there are no per-page processes.

  Pages without embedded text (scans, text drawn as outlines) come back as `""`.
  OCR is deferred (see the app README, "Slide text extraction").
  """

  # Kills pdftotext if a hostile or huge PDF keeps it busy.
  @timeout_seconds 120

  @doc "True when `pdftotext` is on the PATH."
  def available?, do: not is_nil(System.find_executable("pdftotext"))

  def extract(path, opts \\ []) do
    max_pages = Keyword.get(opts, :max_pages, 300)
    # Absolute, so the path can never be read as a pdftotext option.
    path = Path.expand(path)

    cond do
      not File.regular?(path) -> {:error, :enoent}
      not available?() -> {:error, :pdftotext_not_found}
      true -> run(path, max_pages)
    end
  end

  defp run(path, max_pages) do
    args = ["-enc", "UTF-8", "-q", "-l", Integer.to_string(max_pages), path, "-"]
    {cmd, args} = with_timeout(System.find_executable("pdftotext"), args)

    case System.cmd(cmd, args) do
      {out, 0} -> {:ok, split_pages(out)}
      # pdftotext: 1 = can't open (damaged, encrypted), 3 = permissions
      {_, code} when code in [1, 3] -> {:error, :unreadable_pdf}
      {_, code} when code in [124, 137] -> {:error, :timeout}
      {_, code} -> {:error, {:pdftotext_exit, code}}
    end
  end

  # coreutils `timeout` is in the Debian image. On Windows (dev only) the
  # `timeout` on PATH is a different program, so run without it.
  defp with_timeout(exe, args) do
    timeout = System.find_executable("timeout")

    if match?({:unix, _}, :os.type()) and timeout do
      {timeout, ["-s", "KILL", Integer.to_string(@timeout_seconds), exe | args]}
    else
      {exe, args}
    end
  end

  @doc """
  Splits `pdftotext` output into per-page text. pdftotext ends every page,
  including the last, with a form feed.
  """
  def split_pages(""), do: []

  def split_pages(out) do
    pages = String.split(out, "\f")
    pages = if List.last(pages) == "", do: Enum.drop(pages, -1), else: pages
    Enum.map(pages, &Takeaway.Slides.Extractor.clean_text/1)
  end
end
