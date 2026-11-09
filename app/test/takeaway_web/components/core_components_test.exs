defmodule TakeawayWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import TakeawayWeb.CoreComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp has?(html, selector), do: query(html, selector) |> Enum.count() > 0

  describe "flash/1" do
    test "info uses role=status and error uses role=alert" do
      info = render_component(&flash/1, kind: :info, flash: %{"info" => "Saved"})
      error = render_component(&flash/1, kind: :error, flash: %{"error" => "Boom"})
      assert has?(info, "#flash-info[role=status]")
      assert has?(error, "#flash-error[role=alert]")
    end
  end

  describe "button/1" do
    test "renders a <button> with the variant's colors and keeps extra classes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.button id="b" variant="danger" size="lg" class="w-full" phx-click="go">Go</.button>
        """)

      assert has?(html, "button#b.bg-danger.w-full[phx-click='go']")
      refute has?(html, "button#b.bg-brand")
    end

    test "renders a link when given navigate" do
      assigns = %{}
      html = rendered_to_string(~H|<.button id="l" navigate="/speeches/new">New</.button>|)

      assert has?(html, "a#l[href='/speeches/new'].bg-brand")
    end

    test "submit buttons carry a spinner shown only while the form submits" do
      assigns = %{}
      html = rendered_to_string(~H|<.button type="submit">Save</.button>|)

      assert has?(html, "button[type='submit'] svg.animate-spin.hidden")
      refute has?(rendered_to_string(~H|<.button>Save</.button>|), "svg")
    end
  end

  describe "badge/1, card/1 and empty_state/1" do
    test "badge applies its tone" do
      assigns = %{}
      html = rendered_to_string(~H|<.badge tone="brand" id="t">elixir</.badge>|)

      assert has?(html, "span#t.bg-brand-soft")
      assert html =~ "elixir"
    end

    test "card renders a titled section and passes attributes through" do
      assigns = %{}
      html = rendered_to_string(~H|<.card id="c" tone="sunken" title="Materials">Body</.card>|)

      assert has?(html, "section#c.bg-sunken h2")
      assert html =~ "Materials"
    end

    test "empty state shows title, text and actions" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.empty_state id="e" title="No questions yet">
          They appear here.
          <:actions><a id="act" href="/">Go</a></:actions>
        </.empty_state>
        """)

      assert has?(html, "#e h2")
      assert has?(html, "#e a#act")
      assert html =~ "They appear here."
    end
  end

  describe "input/1" do
    test "textarea defaults to 4 rows and respects an explicit rows" do
      assigns = %{}

      assert has?(
               rendered_to_string(~H|<.input name="n" id="n" type="textarea" value="" />|),
               "textarea#n[rows='4']"
             )

      assert has?(
               rendered_to_string(
                 ~H|<.input name="n" id="n" type="textarea" value="" rows="2" />|
               ),
               "textarea#n[rows='2']"
             )
    end

    test "shows errors and hints" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.input name="t" id="t" value="" label="Title" hint="Short is fine." errors={["can't be blank"]} />
        """)

      assert has?(html, "input#t.border-danger")
      assert html =~ "Short is fine."
      assert html =~ "can&#39;t be blank"
    end
  end

  test "logo renders the mark and, by default, the wordmark" do
    assigns = %{}

    assert rendered_to_string(~H|<.logo />|) =~ "away"
    refute rendered_to_string(~H|<.logo wordmark={false} />|) =~ "away"
  end
end
