defmodule Takeaway.Slides.Slide do
  @moduledoc "Text extracted from one slide (page) of a speech's slide deck, numbered from 1."
  use Ecto.Schema
  import Ecto.Changeset

  schema "slides" do
    field :slide_number, :integer
    field :text, :string, default: ""

    belongs_to :speech, Takeaway.Speeches.Speech

    timestamps(type: :utc_datetime)
  end

  @doc """
  `speech_id` is not cast from `attrs`: set it on the struct first
  (`%Slide{speech_id: speech.id}`) or with `put_change/3`.
  """
  def changeset(slide, attrs) do
    slide
    |> cast(attrs, [:slide_number, :text])
    |> validate_required([:speech_id, :slide_number])
    |> validate_number(:slide_number, greater_than: 0)
    |> assoc_constraint(:speech)
    |> unique_constraint([:speech_id, :slide_number])
  end
end
