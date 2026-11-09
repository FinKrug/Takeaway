defmodule Takeaway.SlideFixtures do
  @moduledoc """
  Builds small slide decks for tests, so no binary fixtures are committed.
  """

  @doc """
  A minimal PDF with one page per element of `pages`: a string becomes that
  page's text (ASCII, no parentheses), `nil` a page without any text.
  """
  def pdf(pages) do
    n = length(pages)
    page_refs = Enum.map_join(0..(n - 1), " ", &"#{4 + 2 * &1} 0 R")

    objects =
      [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [#{page_refs}] /Count #{n} >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
      ] ++
        Enum.flat_map(Enum.with_index(pages), fn {text, i} ->
          stream = if text, do: "BT /F1 24 Tf 72 700 Td (#{text}) Tj ET", else: ""

          [
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] " <>
              "/Resources << /Font << /F1 3 0 R >> >> /Contents #{5 + 2 * i} 0 R >>",
            "<< /Length #{byte_size(stream)} >>\nstream\n#{stream}\nendstream"
          ]
        end)

    {body, offsets} =
      objects
      |> Enum.with_index(1)
      |> Enum.reduce({"%PDF-1.4\n", []}, fn {obj, id}, {acc, offsets} ->
        {acc <> "#{id} 0 obj\n#{obj}\nendobj\n", [byte_size(acc) | offsets]}
      end)

    xref =
      "xref\n0 #{length(objects) + 1}\n0000000000 65535 f \n" <>
        (offsets
         |> Enum.reverse()
         |> Enum.map_join(&(String.pad_leading(Integer.to_string(&1), 10, "0") <> " 00000 n \n")))

    body <>
      xref <>
      "trailer\n<< /Size #{length(objects) + 1} /Root 1 0 R >>\nstartxref\n#{byte_size(body)}\n%%EOF\n"
  end

  @doc """
  A minimal `.pptx` (zip) with the given slide XML bodies. `order` lists the
  slide file numbers in presentation order (default: 1..n).
  """
  def pptx(slide_xmls, order \\ nil) do
    n = length(slide_xmls)
    order = order || Enum.to_list(1..n)

    sld_ids =
      Enum.map_join(order, "", fn i -> ~s(<p:sldId id="#{255 + i}" r:id="rId#{i + 1}"/>) end)

    rels =
      Enum.map_join(1..n, "", fn i ->
        ~s(<Relationship Id="rId#{i + 1}" ) <>
          ~s(Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" ) <>
          ~s(Target="slides/slide#{i}.xml"/>)
      end)

    files =
      [
        {~c"ppt/presentation.xml",
         ~s(<?xml version="1.0"?><p:presentation xmlns:p="p" xmlns:r="r"><p:sldIdLst>#{sld_ids}</p:sldIdLst></p:presentation>)},
        {~c"ppt/_rels/presentation.xml.rels",
         ~s(<?xml version="1.0"?><Relationships xmlns="rel">#{rels}</Relationships>)}
      ] ++
        for {xml, i} <- Enum.with_index(slide_xmls, 1) do
          {String.to_charlist("ppt/slides/slide#{i}.xml"), xml}
        end

    {:ok, {_, bin}} = :zip.create(~c"deck.pptx", files, [:memory])
    bin
  end

  @doc "Slide XML whose paragraphs hold the given text runs."
  def slide_xml(paragraphs) do
    body =
      Enum.map_join(paragraphs, "", fn runs ->
        "<a:p>" <> Enum.map_join(List.wrap(runs), "", &"<a:r><a:t>#{&1}</a:t></a:r>") <> "</a:p>"
      end)

    ~s(<?xml version="1.0"?><p:sld xmlns:a="a" xmlns:p="p"><p:cSld><p:spTree>) <>
      ~s(<p:sp><p:txBody>#{body}</p:txBody></p:sp></p:spTree></p:cSld></p:sld>)
  end
end
