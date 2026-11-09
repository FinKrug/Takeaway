defmodule TakeawayWeb.ReflowMotionTest do
  @moduledoc """
  WCAG 1.4.4 / 1.4.10 (reflow), 2.5.8 (target size), 2.3.3 (motion).
  """
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  @css File.read!(Path.expand("../../assets/css/app.css", __DIR__))

  test "reduced motion disables animations and transitions globally" do
    [_, block] = Regex.run(~r/@media \(prefers-reduced-motion: reduce\) \{(.*?)\n\}/s, @css)
    assert block =~ "animation-duration: 1ms"
    assert block =~ "animation-iteration-count: 1"
    assert block =~ "transition-duration: 1ms"
    assert block =~ "scroll-behavior: auto"
  end

  test "body wraps long words so content reflows at 320px" do
    assert @css =~ "overflow-wrap: break-word"
  end

  test "button sizes are at least 24px tall (2.5.8)" do
    for size <- ~w(sm md lg) do
      classes = TakeawayWeb.CoreComponents.button_classes("ghost", size) |> List.flatten()
      h = Enum.find(classes, &(is_binary(&1) and &1 =~ ~r/(^| )h-\d+/))
      [_, n] = Regex.run(~r/h-(\d+)/, h)
      # Tailwind spacing unit is 4px
      assert String.to_integer(n) * 4 >= 24
    end
  end

  test "spinner and badges respect reduced motion and wrap" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <TakeawayWeb.CoreComponents.spinner />
      <TakeawayWeb.CoreComponents.badge tone="success">Answered</TakeawayWeb.CoreComponents.badge>
      """)

    assert html =~ "motion-safe:animate-spin"
    refute html =~ ~r/class="animate-spin/
    assert html =~ "Answered"
    refute html =~ "whitespace-nowrap"
  end
end
