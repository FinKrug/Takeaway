defmodule Takeaway.Questions.FilterTest do
  use ExUnit.Case, async: true

  alias Takeaway.Questions.Filter

  test "accepts questions, fillers, Unicode, and clean substrings" do
    for text <- [
          "How does it scale",
          "So, can you repeat that",
          "What's the latency",
          "Is this class assessed?",
          "How is Scunthorpe connected?",
          "Can we discuss classification",
          "Is café supported ☕?",
          "A statement?"
        ] do
      assert :ok = Filter.check(text)
      assert {:ok, ^text} = Filter.filter(text)
    end
  end

  test "rejects profanity and common disguises without echoing it" do
    for word <- ["FUCK", "sh1t", "f.u.c.k", "F u c k", "f*uck", "ｆｕｃｋ", "a$$hole"] do
      assert {:error, "please rephrase your question without profanity"} =
               Filter.check("Why is this #{word}?")
    end

    assert {:error, _} = Filter.check("Why f u c k I?")
  end

  test "does not join ordinary words or numbers into profanity" do
    for text <- [
          "What is the cache's hit rate?",
          "Is 5 hit points enough?",
          "Section 5: hit rate?",
          "What is the cache’s hit rate?",
          "Does this hit the cache?"
        ] do
      assert :ok = Filter.check(text)
    end
  end

  test "rejects missing text, statements, and punctuation or emoji alone" do
    for text <- [nil, "", "  \n", 42, "Thanks everyone", "Have a great day", "???", "🎉?"] do
      assert {:error, _} = Filter.check(text)
    end
  end

  test "bounds long inputs and rejects invalid UTF-8" do
    assert {:error, _} = Filter.check(String.duplicate("a", 2_001) <> "?")
    assert {:error, _} = Filter.check(String.duplicate("☕", 10_000))
    assert {:error, _} = Filter.check(<<255>>)
    assert :ok = Filter.check("Why " <> String.duplicate("a", 1_995) <> "?")
  end
end
