defmodule TakeawayWeb.CoreComponents do
  @moduledoc """
  Takeaway's UI kit: hand-written Tailwind components, mobile first. No daisyUI.

  Colors, fonts and motion come from the theme tokens in `assets/css/app.css`
  (`bg-surface`, `text-ink`, `text-muted`, `bg-brand`, `border-line`, ...), so
  every component works in light and dark mode. `app/README.md` ("UI kit") has
  an overview.

    * Actions: `button/1`
    * Containers: `card/1`, `header/1`, `empty_state/1`
    * Forms: `input/1` (text, textarea, select, checkbox, ...), `file_input_class/0`
    * Status: `badge/1`, `live_dot/1`, `spinner/1`, `flash/1`
    * Data: `table/1`, `list/1`
    * Brand: `logo/1`, `icon/1`
  """
  use Phoenix.Component
  use Gettext, backend: TakeawayWeb.Gettext

  alias Phoenix.LiveView.JS

  ## Brand

  @doc """
  Renders the Takeaway mark, optionally with the wordmark.

  ## Examples

      <.logo />
      <.logo class="h-10" wordmark={false} />
  """
  attr :class, :any, default: "h-8"
  attr :wordmark, :boolean, default: true

  def logo(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-2", @class]}>
      <svg viewBox="0 0 32 32" class="h-full w-auto shrink-0" aria-hidden="true">
        <rect width="32" height="32" rx="9" class="fill-brand" />
        <path
          d="M9 11.5A3.5 3.5 0 0 1 12.5 8h7A3.5 3.5 0 0 1 23 11.5v5a3.5 3.5 0 0 1-3.5 3.5H15l-4.2 3.4c-.5.4-1.3 0-1.3-.6V20.6A3.5 3.5 0 0 1 9 17.5v-6Z"
          class="fill-on-brand"
        />
        <path d="M13 13.25h6M13 16h4" class="stroke-brand" stroke-width="1.8" stroke-linecap="round" />
      </svg>

      <span
        :if={@wordmark}
        class="font-display text-[1.05em] font-semibold tracking-tight text-ink"
      >
        take<span class="text-brand">away</span>
      </span>
    </span>
    """
  end

  ## Flash

  @doc """
  Renders flash notices. Full width at the top on phones, a toast at the top
  right from `sm` up.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="fixed inset-x-0 top-0 z-50 flex justify-center p-3 sm:inset-x-auto sm:right-0 sm:justify-end sm:p-4"
      {@rest}
    >
      <div class={[
        "flex w-full max-w-sm cursor-pointer items-start gap-3 rounded-2xl border p-3.5 text-sm shadow-lg shadow-black/5",
        "motion-safe:animate-pop",
        @kind == :info && "border-line bg-surface text-ink",
        @kind == :error && "border-danger/30 bg-danger-soft text-ink"
      ]}>
        <.icon
          :if={@kind == :info}
          name="hero-information-circle"
          class="mt-0.5 size-5 shrink-0 text-brand"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="mt-0.5 size-5 shrink-0 text-danger"
        />
        <div class="min-w-0 flex-1">
          <p :if={@title} class="font-semibold">{@title}</p>

          <p class="text-pretty">{msg}</p>
        </div>

        <button
          type="button"
          class="-m-1 rounded-lg p-1 text-muted transition-colors hover:bg-sunken hover:text-ink"
          aria-label={gettext("close")}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
    </div>
    """
  end

  ## Buttons

  @doc """
  Renders a button, or a link styled as one when given `href`, `navigate` or `patch`.

  `variant` is `primary` (default), `secondary`, `ghost` or `danger`; `size` is
  `sm`, `md` (default) or `lg`. Extra classes in `class` are added, not replaced,
  so `class="w-full"` makes a full-width button. Submit buttons show a spinner
  while their form is submitting.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="secondary" size="sm">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
      <.button type="submit" size="lg" class="w-full">Create speech</.button>
  """
  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type form)

  attr :class, :any, default: nil
  attr :variant, :string, default: "primary", values: ~w(primary secondary ghost danger)
  attr :size, :string, default: "md", values: ~w(sm md lg)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :classes, button_classes(assigns.variant, assigns.size, assigns.class))

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@classes} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      assigns = assign(assigns, :submit?, rest[:type] == "submit")

      ~H"""
      <button class={@classes} {@rest}>
        <.spinner :if={@submit?} class="hidden size-4 phx-submit-loading:inline-block" /> {render_slot(
          @inner_block
        )}
      </button>
      """
    end
  end

  @doc false
  def button_classes(variant, size, extra \\ nil) do
    [
      "inline-flex select-none items-center justify-center gap-2 rounded-xl font-semibold",
      "transition-[background-color,border-color,color,box-shadow,transform] duration-150 ease-out",
      "active:scale-[0.98] disabled:pointer-events-none disabled:opacity-50",
      "phx-submit-loading:opacity-80 phx-click-loading:opacity-80",
      case size do
        "sm" -> "h-9 px-3 text-sm"
        "md" -> "h-11 px-4 text-[0.9375rem]"
        "lg" -> "h-13 px-6 text-base"
      end,
      case variant do
        "primary" ->
          "bg-brand text-on-brand shadow-sm shadow-brand/20 hover:bg-brand-strong hover:shadow-md hover:shadow-brand/25"

        "secondary" ->
          "border border-line bg-surface text-ink shadow-sm shadow-black/5 hover:border-ink/20 hover:bg-sunken"

        "ghost" ->
          "text-ink hover:bg-sunken"

        "danger" ->
          "bg-danger text-white shadow-sm shadow-danger/20 hover:brightness-95 hover:shadow-md"
      end,
      extra
    ]
  end

  ## Containers

  @doc """
  Renders a card: the basic surface for grouping content.

  `tone` is `default` (raised surface), `sunken`, `brand` (tinted, for the one
  thing to look at) or `dashed` (placeholders). Pass `id` and other attributes
  through as usual.

  ## Examples

      <.card id="join-info" tone="brand">...</.card>
      <.card title="Speech summary">...</.card>
  """
  attr :tone, :string, default: "default", values: ~w(default sunken brand dashed)
  attr :title, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true
  slot :actions, doc: "optional actions shown next to the title"

  def card(assigns) do
    ~H"""
    <section
      class={[
        "rounded-2xl p-4 sm:p-5",
        @tone == "default" && "border border-line bg-surface shadow-sm shadow-black/[0.03]",
        @tone == "sunken" && "bg-sunken",
        @tone == "brand" && "border border-brand/25 bg-brand-soft",
        @tone == "dashed" && "border border-dashed border-line",
        @class
      ]}
      {@rest}
    >
      <div :if={@title || @actions != []} class="mb-3 flex items-center justify-between gap-3">
        <h2 :if={@title} class="font-display text-base font-semibold tracking-tight">{@title}</h2>

        <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  Renders a page header with title, optional subtitle and actions. Actions sit
  under the title on phones and to its right from `sm` up.
  """
  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[
      "flex flex-col gap-3 pb-2",
      @actions != [] && "sm:flex-row sm:items-end sm:justify-between",
      @class
    ]}>
      <div class="min-w-0">
        <h1 class="font-display text-2xl font-semibold tracking-tight text-balance sm:text-[1.75rem] sm:leading-tight">
          {render_slot(@inner_block)}
        </h1>

        <p :if={@subtitle != []} class="mt-1.5 text-pretty text-muted">
          {render_slot(@subtitle)}
        </p>
      </div>

      <div :if={@actions != []} class="flex shrink-0 flex-wrap gap-2">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders an empty state: an icon, a title, a line of explanation and optional actions.

  ## Examples

      <.empty_state icon="hero-chat-bubble-left-right" title="No questions yet">
        Questions from attendees will appear here.
      </.empty_state>
  """
  attr :icon, :string, default: "hero-sparkles"
  attr :title, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block
  slot :actions

  def empty_state(assigns) do
    ~H"""
    <div
      class={[
        "flex flex-col items-center rounded-2xl border border-dashed border-line px-6 py-10 text-center",
        @class
      ]}
      {@rest}
    >
      <span class="mb-3 grid size-11 place-items-center rounded-full bg-brand-soft text-brand">
        <.icon name={@icon} class="size-5" />
      </span>

      <h2 class="font-display font-semibold tracking-tight">{@title}</h2>

      <p :if={@inner_block != []} class="mt-1 max-w-sm text-pretty text-sm text-muted">
        {render_slot(@inner_block)}
      </p>

      <div :if={@actions != []} class="mt-5 flex flex-wrap justify-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  ## Status

  @doc """
  Renders a badge (or chip, for tags). `tone` is `neutral` (default), `brand`,
  `success`, `danger`, `warning` or `outline`.

  ## Examples

      <.badge tone="brand">elixir</.badge>
      <.badge tone="danger"><.live_dot /> Live</.badge>
  """
  attr :tone, :string,
    default: "neutral",
    values: ~w(neutral brand success danger warning outline)

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold",
        @tone == "neutral" && "bg-sunken text-ink",
        @tone == "brand" && "bg-brand-soft text-brand-strong",
        @tone == "success" && "bg-success-soft text-success",
        @tone == "danger" && "bg-danger-soft text-danger",
        @tone == "warning" && "bg-warning-soft text-warning",
        @tone == "outline" && "border border-line text-muted",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc "A small pulsing dot for live status, colored by the surrounding text."
  attr :class, :any, default: nil

  def live_dot(assigns) do
    ~H"""
    <span class={["relative inline-flex size-2", @class]} aria-hidden="true">
      <span class="absolute inline-flex size-full rounded-full bg-current opacity-60 motion-safe:animate-ping" />
      <span class="relative inline-flex size-2 rounded-full bg-current" />
    </span>
    """
  end

  @doc "A spinner for loading states; inherits the text color."
  attr :class, :any, default: "size-4"

  def spinner(assigns) do
    ~H"""
    <svg class={["animate-spin", @class]} viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <circle cx="12" cy="12" r="9" stroke="currentColor" stroke-opacity=".25" stroke-width="3" />
      <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" stroke-width="3" stroke-linecap="round" />
    </svg>
    """
  end

  ## Forms

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`, styled
      with `file_input_class/0`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  <.input field={@form[:notes]} type="textarea" hint="Only you can see these." />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :hint, :string, default: nil, doc: "helper text under the field"
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete autocapitalize capture cols disabled enterkeyhint form
                inputmode list max maxlength min minlength multiple pattern placeholder
                readonly required rows size spellcheck step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label for={@id} class="flex cursor-pointer items-center gap-3 text-sm font-medium">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "size-5 rounded-md border-line accent-[var(--tk-brand)]"}
          aria-invalid={@errors != [] && "true"}
          aria-describedby={describedby(@id, @errors, @hint)}
          {@rest}
        /> {@label}
      </label>

      <.field_hint :if={@hint} id={hint_id(@id)}>{@hint}</.field_hint>

      <.error :for={{msg, i} <- Enum.with_index(@errors)} id={error_id(@id, i)}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <label for={@id} class="block">
        <.field_label :if={@label} required={required?(@rest)}>{@label}</.field_label>

        <select
          id={@id}
          name={@name}
          class={[
            @class || [field_classes(), "appearance-none pr-10"],
            @errors != [] && (@error_class || field_error_classes())
          ]}
          multiple={@multiple}
          aria-invalid={@errors != [] && "true"}
          aria-required={required?(@rest) && "true"}
          aria-describedby={describedby(@id, @errors, @hint)}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>

      <.field_hint :if={@hint} id={hint_id(@id)}>{@hint}</.field_hint>

      <.error :for={{msg, i} <- Enum.with_index(@errors)} id={error_id(@id, i)}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    assigns = update(assigns, :rest, &Map.put_new(&1, :rows, 4))

    ~H"""
    <div>
      <label for={@id} class="block">
        <.field_label :if={@label} required={required?(@rest)}>{@label}</.field_label>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || [field_classes(), "min-h-24 resize-y py-3 leading-relaxed"],
            @errors != [] && (@error_class || field_error_classes())
          ]}
          aria-invalid={@errors != [] && "true"}
          aria-required={required?(@rest) && "true"}
          aria-describedby={describedby(@id, @errors, @hint)}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>

      <.field_hint :if={@hint} id={hint_id(@id)}>{@hint}</.field_hint>

      <.error :for={{msg, i} <- Enum.with_index(@errors)} id={error_id(@id, i)}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div>
      <label for={@id} class="block">
        <.field_label :if={@label} required={required?(@rest)}>{@label}</.field_label>

        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || [field_classes(), "h-11"],
            @errors != [] && (@error_class || field_error_classes())
          ]}
          aria-invalid={@errors != [] && "true"}
          aria-required={required?(@rest) && "true"}
          aria-describedby={describedby(@id, @errors, @hint)}
          {@rest}
        />
      </label>

      <.field_hint :if={@hint} id={hint_id(@id)}>{@hint}</.field_hint>

      <.error :for={{msg, i} <- Enum.with_index(@errors)} id={error_id(@id, i)}>{msg}</.error>
    </div>
    """
  end

  # 16px text on phones stops iOS Safari from zooming into focused fields.
  defp field_classes do
    "block w-full rounded-xl border border-line bg-surface px-3.5 text-base text-ink shadow-sm shadow-black/[0.02] " <>
      "placeholder:text-muted/70 transition-[border-color,box-shadow] duration-150 " <>
      "hover:border-ink/25 focus:border-brand focus:outline-none focus:ring-4 focus:ring-brand/15 " <>
      "disabled:cursor-not-allowed disabled:opacity-60 sm:text-[0.9375rem]"
  end

  defp field_error_classes, do: "border-danger focus:border-danger focus:ring-danger/15"

  @doc """
  Classes for `Phoenix.Component.live_file_input/1`, matching the other fields.

      <.live_file_input upload={@uploads.slides} class={file_input_class()} />
  """
  def file_input_class do
    "block w-full cursor-pointer rounded-xl border border-dashed border-line bg-surface p-2 text-sm text-muted " <>
      "transition-colors hover:border-brand/50 " <>
      "file:mr-3 file:cursor-pointer file:rounded-lg file:border-0 file:bg-brand-soft file:px-3 file:py-2 " <>
      "file:text-sm file:font-semibold file:text-brand-strong"
  end

  @doc "A form label, for fields not rendered with `input/1` (for example file uploads)."
  attr :required, :boolean, default: false
  slot :inner_block, required: true

  def field_label(assigns) do
    ~H"""
    <span class="mb-1.5 block text-sm font-semibold text-ink">
      {render_slot(@inner_block)}<span :if={@required} aria-hidden="true" class="ml-0.5 text-danger">*</span>
    </span>
    """
  end

  defp required?(rest), do: rest[:required] in [true, "true", "required", ""]
  defp hint_id(id), do: "#{id}-hint"
  defp error_id(id, i), do: "#{id}-error-#{i}"

  defp describedby(id, errors, hint) do
    ids =
      if(hint, do: [hint_id(id)], else: []) ++
        Enum.map(Enum.with_index(errors), fn {_, i} -> error_id(id, i) end)

    if ids == [], do: nil, else: Enum.join(ids, " ")
  end

  attr :id, :string, default: nil
  slot :inner_block, required: true

  defp field_hint(assigns) do
    ~H"""
    <p id={@id} class="mt-1.5 text-sm text-muted">{render_slot(@inner_block)}</p>
    """
  end

  # Helper used by inputs to generate form errors
  attr :id, :string, default: nil
  slot :inner_block, required: true

  defp error(assigns) do
    ~H"""
    <p id={@id} role="alert" class="mt-1.5 flex items-center gap-1.5 text-sm font-medium text-danger">
      <.icon name="hero-exclamation-circle-mini" class="size-4 shrink-0" /> {render_slot(@inner_block)}
    </p>
    """
  end

  ## Data

  @doc """
  Renders a table. It scrolls sideways on narrow screens instead of breaking the layout.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="-mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
      <table class="w-full text-left text-sm">
        <thead class="text-xs uppercase tracking-wide text-muted">
          <tr>
            <th :for={col <- @col} class="px-3 py-2 font-semibold">{col[:label]}</th>

            <th :if={@action != []} class="px-3 py-2">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>

        <tbody
          id={@id}
          phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
          class="divide-y divide-line border-t border-line"
        >
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class="transition-colors hover:bg-sunken/60"
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={["px-3 py-3", @row_click && "hover:cursor-pointer"]}
            >
              {render_slot(col, @row_item.(row))}
            </td>

            <td :if={@action != []} class="w-0 px-3 py-3 font-semibold">
              <div class="flex gap-4">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <dl class="divide-y divide-line">
      <div :for={item <- @item} class="py-3 sm:grid sm:grid-cols-3 sm:gap-4">
        <dt class="text-sm font-semibold text-muted">{item.title}</dt>

        <dd class="mt-1 sm:col-span-2 sm:mt-0">{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} aria-hidden="true" />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(TakeawayWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(TakeawayWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
