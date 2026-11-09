# Takeaway (Phoenix app)

See the [root README](../README.md) for what the app does, configuration and deployment.

```bash
mix setup        # deps, database, assets
mix phx.server   # http://localhost:4000 (or iex -S mix phx.server)
mix test
```

## UI kit

Mobile first, hand-written Tailwind v4. No daisyUI. Build pages from these instead of
styling raw HTML, so speaker and attendee pages look the same and work in light and dark mode.

**Theme tokens** (`assets/css/app.css`). Use these, not raw Tailwind colors:

| Token | Use |
|---|---|
| `bg-canvas`, `bg-surface`, `bg-sunken` | page background, cards, wells and inputs |
| `text-ink`, `text-muted`, `border-line` | body text, secondary text, borders |
| `bg-brand`, `text-brand`, `bg-brand-strong`, `bg-brand-soft`, `text-on-brand` | Takeaway tangerine: primary actions, highlights, tints |
| `success`, `danger`, `warning` (+ `-soft`) | status colors |
| `font-sans`, `font-display`, `font-mono` | UI text, headings, join codes and timestamps |
| `animate-enter`, `animate-pop` | entrance motion (wrap in `motion-safe:`) |

Light and dark values switch on `<html data-theme>`; the toggle is in the header.

**Layout.** Every page renders inside `<Layouts.app flash={@flash}>`: a sticky header
(logo, Join, New speech, theme toggle), a single column capped at `max-w-2xl` (`wide` for
`max-w-5xl`), children spaced with `space-y-6`, and a footer. It respects phone safe areas.

**Components** (`lib/takeaway_web/components/core_components.ex`, docs on each function):

| Component | Notes |
|---|---|
| `<.button>` | `variant`: primary, secondary, ghost, danger. `size`: sm, md, lg. `class` adds (`w-full`). Becomes a link with `navigate`/`href`/`patch`. Submit buttons show a spinner while the form submits. |
| `<.card>` | `tone`: default, sunken, brand, dashed. Optional `title` and `:actions` slot. |
| `<.header>` | Page title with `:subtitle` and `:actions` slots. |
| `<.input>` | text, textarea (4 rows by default), select, checkbox, ...; `label`, `hint`, errors. 16px text on phones so iOS doesn't zoom. |
| `file_input_class/0`, `<.field_label>` | Style `live_file_input` uploads to match. |
| `<.badge>` | Tags and chips. `tone`: neutral, brand, success, danger, warning, outline. |
| `<.empty_state>` | Icon, title, text and `:actions`, for "nothing here yet". |
| `<.live_dot>`, `<.spinner>` | Live status and loading states. |
| `<.logo>`, `<.icon>` | Brand mark (with or without wordmark) and Heroicons. |

Interaction defaults: buttons press in (`active:scale`), fields get a brand focus ring,
LiveView navigations show the brand-colored top bar and the content fades in. All motion is
skipped for people who ask for reduced motion.

## Post-speech summaries

The speaker's **End Speech** button sets `ended_at` and broadcasts `{:speech_ended, speech}`.
`Takeaway.Summaries` then generates, once, and caches in the `summaries` table:

* a speaker summary (shown on `/speeches/:code`): prose summary, top question groups
  (by `group_id`) and the time buckets where questions spiked;
* an attendee summary per user (shown on `/join/:code` when the session has a `user_id`):
  cliffnotes merged with that attendee's own notes, generated on first view.

Prose comes from `Takeaway.LLM`. Set `ANTHROPIC_API_KEY` (optionally `ANTHROPIC_MODEL`) to use
Claude; without it, or if the call fails, an extractive fallback is stored. Speeches with no
transcript and/or no questions yield a summary that says so.
