defmodule Takeaway.Questions.Group do
  @moduledoc "A speech's question group. Active membership counts are derived from questions."
  use Ecto.Schema

  schema "question_groups" do
    field :text, :string
    field :count, :integer, virtual: true, default: 0
    belongs_to :speech, Takeaway.Speeches.Speech
    timestamps(type: :utc_datetime)
  end
end
