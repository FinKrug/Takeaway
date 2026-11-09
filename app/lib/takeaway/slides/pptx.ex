defmodule Takeaway.Slides.Pptx do
  @moduledoc """
  Text from `.pptx` decks without external tools: a `.pptx` is a zip of XML
  parts. Slide order comes from `ppt/presentation.xml` (falling back to the
  `slideN.xml` numbers), and a slide's text is its `<a:t>` runs, one line per
  `<a:p>` paragraph.

  The file is untrusted, so each part is inflated with a hard size cap
  (no zip bombs) and the XML is scanned with regular expressions instead of a
  parser (no entity expansion).
  """
  alias Takeaway.Slides.Extractor

  # Uncompressed size cap per XML part.
  @max_part_bytes 5_000_000

  def extract(path, opts \\ []) do
    max_pages = Keyword.get(opts, :max_pages, 300)

    with true <- File.regular?(path) || {:error, :enoent},
         {:ok, entries} <- list_entries(path),
         {:ok, fd} <- File.open(path, [:read, :binary]) do
      try do
        slide_names = slide_order(fd, entries) |> Enum.take(max_pages)

        texts =
          Enum.map(slide_names, fn name ->
            case read_part(fd, entries[name]) do
              {:ok, xml} -> slide_text(xml)
              {:error, _} -> ""
            end
          end)

        {:ok, texts}
      after
        File.close(fd)
      end
    end
  end

  defp list_entries(path) do
    case :zip.list_dir(String.to_charlist(path)) do
      {:ok, list} ->
        entries =
          for {:zip_file, name, _info, _comment, offset, comp_size} <- list,
              into: %{},
              do: {List.to_string(name), {offset, comp_size}}

        if Map.has_key?(entries, "ppt/presentation.xml"),
          do: {:ok, entries},
          else: {:error, :not_a_pptx}

      {:error, _} ->
        {:error, :not_a_pptx}
    end
  end

  # Slide part names in presentation order.
  defp slide_order(fd, entries) do
    from_presentation =
      with {:ok, pres} <- read_part(fd, entries["ppt/presentation.xml"]),
           {:ok, rels} <- read_part(fd, entries["ppt/_rels/presentation.xml.rels"]) do
        targets =
          for attrs <- tags(rels, "Relationship"), into: %{} do
            {attrs["Id"], rel_target(attrs["Target"])}
          end

        for attrs <- tags(pres, "p:sldId"),
            name <- [targets[attrs["r:id"]]],
            Map.has_key?(entries, name),
            do: name
      else
        _ -> []
      end

    if from_presentation != [] do
      from_presentation
    else
      entries
      |> Map.keys()
      |> Enum.flat_map(fn name ->
        case Regex.run(~r{^ppt/slides/slide(\d+)\.xml$}, name) do
          [_, n] -> [{String.to_integer(n), name}]
          _ -> []
        end
      end)
      |> Enum.sort()
      |> Enum.map(&elem(&1, 1))
    end
  end

  defp rel_target(nil), do: nil
  defp rel_target("/" <> abs), do: abs
  defp rel_target(rel), do: "ppt/" <> rel

  # Attribute maps of every `<name ...>` tag in `xml`.
  defp tags(xml, name) do
    ~r/<#{Regex.escape(name)}\s([^>]*?)\/?>/
    |> Regex.scan(xml, capture: :all_but_first)
    |> Enum.map(fn [attrs] ->
      for [k, v] <- Regex.scan(~r/([\w:]+)="([^"]*)"/, attrs, capture: :all_but_first),
          into: %{},
          do: {k, unescape(v)}
    end)
  end

  @doc false
  def slide_text(xml) do
    xml
    |> String.split("</a:p>")
    |> Enum.map(fn para ->
      ~r/<a:t(?:\s[^>]*)?>([^<]*)<\/a:t>/
      |> Regex.scan(para, capture: :all_but_first)
      |> Enum.map_join(fn [t] -> unescape(t) end)
    end)
    |> Enum.join("\n")
    |> Extractor.clean_text()
  end

  defp unescape(s) do
    Regex.replace(~r/&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);/, s, fn whole, ent ->
      case ent do
        "amp" -> "&"
        "lt" -> "<"
        "gt" -> ">"
        "quot" -> "\""
        "apos" -> "'"
        "#x" <> hex -> codepoint(String.to_integer(hex, 16), whole)
        "#" <> dec -> codepoint(String.to_integer(dec), whole)
      end
    end)
  end

  defp codepoint(cp, fallback) do
    <<cp::utf8>>
  rescue
    ArgumentError -> fallback
  end

  # Reads one zip member through its local header, inflating at most
  # @max_part_bytes.
  defp read_part(_fd, nil), do: {:error, :missing}

  defp read_part(fd, {offset, comp_size}) do
    with {:ok,
          <<0x50, 0x4B, 3, 4, _version::16, _flags::16, method::little-16, _::binary-size(16),
            name_len::little-16, extra_len::little-16>>} <- :file.pread(fd, offset, 30),
         {:ok, data} <- :file.pread(fd, offset + 30 + name_len + extra_len, comp_size) do
      case method do
        0 when byte_size(data) <= @max_part_bytes -> {:ok, data}
        0 -> {:error, :too_large}
        8 -> inflate(data)
        _ -> {:error, :unsupported_compression}
      end
    else
      _ -> {:error, :bad_zip_entry}
    end
  end

  defp inflate(data) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, -15)
      inflate_loop(z, :zlib.safeInflate(z, data), [], 0)
    rescue
      ErlangError -> {:error, :bad_deflate}
    after
      :zlib.close(z)
    end
  end

  defp inflate_loop(z, {status, out}, acc, size) do
    size = size + IO.iodata_length(out)

    cond do
      size > @max_part_bytes -> {:error, :too_large}
      status == :finished -> {:ok, IO.iodata_to_binary([acc | out])}
      status == :continue -> inflate_loop(z, :zlib.safeInflate(z, []), [acc | out], size)
    end
  end

  defp inflate_loop(_z, _other, _acc, _size), do: {:error, :bad_deflate}
end
