defmodule TakeawayWeb.ThemeContrastTest do
  @moduledoc """
  WCAG 1.4.3 / 1.4.11: measures the oklch tokens in app.css for both themes.
  """
  use ExUnit.Case, async: true

  @css File.read!(Path.expand("../../assets/css/app.css", __DIR__))

  defp tokens(theme) do
    [_, block] = Regex.run(~r/\[data-theme="#{theme}"\] \{(.*?)\}/s, @css)

    ~r/--tk-([\w-]+): oklch\(([\d.]+)% ([\d.]+) ([\d.]+)\)/
    |> Regex.scan(block)
    |> Map.new(fn [_, k, l, c, h] -> {k, {f(l) / 100, f(c), f(h)}} end)
  end

  defp f(s), do: s |> Float.parse() |> elem(0)

  defp luminance({l, c, h}) do
    hr = h * :math.pi() / 180
    a = c * :math.cos(hr)
    b = c * :math.sin(hr)
    l_ = :math.pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
    m_ = :math.pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
    s_ = :math.pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
    r = 4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_
    g = -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_
    bl = -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_
    cl = fn x -> x |> max(0.0) |> min(1.0) end
    0.2126 * cl.(r) + 0.7152 * cl.(g) + 0.0722 * cl.(bl)
  end

  defp ratio(a, b) do
    {x, y} = {luminance(a), luminance(b)}
    (max(x, y) + 0.05) / (min(x, y) + 0.05)
  end

  for theme <- ~w(light dark) do
    describe "#{theme} theme" do
      @theme theme

      test "text pairs meet 4.5:1" do
        t = tokens(@theme)

        pairs =
          for bg <- ~w(canvas surface sunken), fg <- ~w(ink muted brand-strong), do: {fg, bg}

        pairs =
          pairs ++
            [{"on-brand", "brand"}, {"on-brand", "brand-strong"}, {"ink", "brand-soft"}] ++
            for k <- ~w(success danger warning),
                bg <- [k <> "-soft", "surface", "canvas"],
                do: {k, bg}

        for {fg, bg} <- pairs do
          assert ratio(t[fg], t[bg]) >= 4.5, "#{fg} on #{bg} in #{@theme}"
        end
      end

      test "control borders and brand meet 3:1" do
        t = tokens(@theme)

        for bg <- ~w(canvas surface sunken) do
          assert ratio(t["control"], t[bg]) >= 3.0, "control on #{bg} in #{@theme}"
        end

        assert ratio(t["brand"], t["surface"]) >= 3.0
      end
    end
  end
end
