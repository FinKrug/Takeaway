defmodule Takeaway.Questions.Filter do
  @moduledoc """
  Pure English-language question and profanity checks. A trailing question mark
  counts as a question. Whole-word matching avoids clean substrings like `class`.
  This basic word list does not detect abusive meaning or every disguise.
  """

  alias Takeaway.Questions

  @words MapSet.new(~w(fuck fucking fucked fucker fuckers motherfucker motherfuckers
                       shit shitty bullshit bitch bitches bastard bastards asshole assholes
                       cunt cunts dickhead dickheads))
  @disguised Regex.compile!(
               "(?<![\\p{L}\\p{N}])(?:" <>
                 Enum.map_join(@words, "|", fn word ->
                   word |> String.graphemes() |> Enum.join("[\\s\\p{P}\\p{S}]*")
                 end) <> ")(?![\\p{L}\\p{N}])",
               "u"
             )
  @max_length 2_000

  @doc "Returns :ok or a friendly error without echoing the rejected text."
  def check(text) when is_binary(text) do
    cond do
      not String.valid?(text) -> {:error, "please enter a valid text question"}
      byte_size(text) > @max_length * 4 -> too_long()
      String.length(text) > @max_length -> too_long()
      String.trim(text) == "" -> {:error, "type a question first"}
      profane?(text) -> {:error, "please rephrase your question without profanity"}
      not Questions.question?(text) -> {:error, "please ask a question about the talk"}
      not Regex.match?(~r/\p{L}/u, text) -> {:error, "please ask a question about the talk"}
      true -> :ok
    end
  end

  def check(_), do: {:error, "type a question first"}

  @doc "Adapter for the submission hook; preserves the original text."
  def filter(text) do
    with :ok <- check(text), do: {:ok, text}
  end

  defp too_long, do: {:error, "please keep your question to 2000 characters or fewer"}

  defp profane?(text) do
    normalized =
      text
      |> String.normalize(:nfkc)
      |> String.downcase()
      |> String.replace(~r/[013457@$]/, fn
        "0" -> "o"
        "1" -> "i"
        "3" -> "e"
        "4" -> "a"
        "5" -> "s"
        "7" -> "t"
        "@" -> "a"
        "$" -> "s"
      end)

    normalized
    |> String.split(~r/[^\p{L}]+/u, trim: true)
    |> Enum.any?(&MapSet.member?(@words, &1)) or Regex.match?(@disguised, normalized)
  end
end
