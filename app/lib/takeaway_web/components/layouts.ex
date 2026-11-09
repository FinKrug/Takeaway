defmodule TakeawayWeb.Layouts do
  @moduledoc """
  Takeaway's layouts: the root HTML skeleton (`layouts/root.html.heex`) and the
  mobile-first app shell, `app/1`, that every page renders inside.
  """
  use TakeawayWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the app shell: a sticky header with the logo, navigation and theme
  toggle; the page content; and a footer.

  Content is a single column sized for phones and capped at `max-w-2xl`
  (`wide` raises it to `max-w-5xl`, for the landing page). It fades in on
  every navigation.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

      <Layouts.app flash={@flash} wide>...</Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :wide, :boolean, default: false, doc: "use a wider content column"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-dvh flex-col">
      <header class="sticky top-0 z-40 border-b border-line/70 bg-canvas/80 pt-[env(safe-area-inset-top)] backdrop-blur-md supports-[backdrop-filter]:bg-canvas/70">
        <nav
          class={[
            "mx-auto flex h-14 w-full items-center justify-between gap-3 px-4 sm:h-16 sm:px-6",
            if(@wide, do: "max-w-5xl", else: "max-w-2xl")
          ]}
          aria-label="Main"
        >
          <.link
            navigate={~p"/"}
            class="-m-1 rounded-lg p-1 transition-opacity hover:opacity-80"
            aria-label="Takeaway home"
            id="nav-home"
          >
            <.logo class="h-7 sm:h-8" />
          </.link>

          <div class="flex items-center gap-1 sm:gap-2">
            <.link
              href={~p"/#join"}
              id="nav-join"
              class="rounded-lg px-2.5 py-2 text-sm font-semibold text-muted transition-colors hover:bg-sunken hover:text-ink"
            >
              Join
            </.link>
            <.button navigate={~p"/speeches/new"} size="sm" id="nav-new-speech">
              <.icon name="hero-plus-mini" class="size-4" />
              <span class="sr-only sm:not-sr-only">New speech</span>
              <span class="sm:hidden" aria-hidden="true">New</span>
            </.button>
            <.theme_toggle />
          </div>
        </nav>
      </header>

      <main
        id="main"
        class={[
          "mx-auto w-full flex-1 px-4 pb-16 pt-6 sm:px-6 sm:pt-10 motion-safe:animate-enter",
          if(@wide, do: "max-w-5xl", else: "max-w-2xl")
        ]}
      >
        <div class="space-y-6">
          {render_slot(@inner_block)}
        </div>
      </main>

      <footer class="border-t border-line/70 pb-[env(safe-area-inset-bottom)]">
        <div class={[
          "mx-auto flex w-full flex-col gap-1 px-4 py-6 text-sm text-muted sm:flex-row sm:items-center sm:justify-between sm:px-6",
          if(@wide, do: "max-w-5xl", else: "max-w-2xl")
        ]}>
          <.logo class="h-5" />
          <p>Questions, notes and summaries for live talks.</p>
        </div>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Light/dark toggle: one button that flips between the two. Following the
  system setting is the default until someone picks one (see the theme script
  in root.html.heex).
  """
  def theme_toggle(assigns) do
    ~H"""
    <span class="contents">
      <button
        type="button"
        id="theme-dark"
        class="grid size-9 place-items-center rounded-lg text-muted transition-colors hover:bg-sunken hover:text-ink dark:hidden"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Switch to dark mode"
      >
        <.icon name="hero-moon-mini" class="size-5" />
      </button>
      <button
        type="button"
        id="theme-light"
        class="hidden size-9 place-items-center rounded-lg text-muted transition-colors hover:bg-sunken hover:text-ink dark:grid"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Switch to light mode"
      >
        <.icon name="hero-sun-mini" class="size-5" />
      </button>
    </span>
    """
  end
end
