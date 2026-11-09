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

## Organizer accounts

Organizers register at `/organizers/register` and log in at `/organizers/log_in`
(PBKDF2-SHA256 password hashes; the session cookie holds only the organizer id).
An organizer owns events (`events.organizer_id`); creating a speech at `/speeches/new`
puts it in the organizer's event, created on first use.

Only the owning organizer can open the organizer pages. Everyone else is redirected
to the login page, or to `/` when the event or speech belongs to someone else:

* `/organizers`: dashboard listing the organizer's events with a **Manage tickets** link
* `/events/:id/tickets`: generate and import tickets
* `/speeches/:code`: speech control page (also links to the tickets and speaker pages)
* `/speeches/:id/speak`: speaker page with the live transcript

`/join/:code` (attendees) stays public. The per-event `admin_token` links no longer
work; the column is left in place and unused.

Events created before organizer accounts have no owner and are closed to everyone until
claimed. After registering, run in the release:

    bin/takeaway rpc 'Takeaway.Release.claim_unowned_events("me@example.com")'

## Slide text extraction

After a speech is created, the text of its slide deck is extracted in the background and
stored per slide (`slides` table: `speech_id`, `slide_number` from 1, `text`), then handed to
`Takeaway.Indexer.index_slide/1`. Code: `Takeaway.Slides`, hooked in `Takeaway.SpeechCreator`.

**Decision (card 302.1):**

| Upload | Handling |
|---|---|
| `.pdf` | Embedded text with poppler's `pdftotext` (`poppler-utils` in the runtime image): one process for the whole deck, pages split on form feeds. |
| `.pptx` | Read in Elixir, no extra tools: `ppt/slides/slideN.xml` from the zip, in `presentation.xml` order, `<a:t>` runs per paragraph. |
| `.ppt` (legacy binary) | Not supported: skipped and logged. Converting needs LibreOffice (hundreds of MB of image, several hundred MB of RAM per conversion), far beyond the 256Mi pod. Export to PDF instead. |
| Pages without text (scans, outlined text) | Stored as `""` (still numbered and indexed). **OCR is deferred.** |

Why OCR is deferred: tesseract plus English data adds roughly 30-40 MB to the image, and OCR
needs each page rendered first (`pdftoppm`, ~300 DPI). Rendering and recognizing a page takes
roughly 1-3 s of CPU and 100-200 MB of RAM, which doesn't fit next to the BEAM in the app
container (500m CPU / 256Mi) without a bigger limit or a separate worker. Most talk decks are
exported from PowerPoint, Keynote or Google Slides with embedded text, which `pdftotext` reads
in milliseconds per page. If OCR is needed later, add it as a `Takeaway.Slides.Extractor` step
for the empty pages, ideally in its own Deployment.

Costs: `poppler-utils` grows the runtime image from about 206 MB to 274 MB (uncompressed,
mostly libpoppler and its shared libraries). `pdftotext` read a generated 100-page PDF in
about 110 ms in the image (~1 ms per page; real decks with more text and fonts take a few ms
per page) and needs a few MB of RAM, outside the BEAM heap. Extractions run one at a time per pod (a lock in `Takeaway.Slides`),
`pdftotext` is killed after 120 s, at most 300 slides are read, and slide text is capped at
20,000 characters (8,000 sent to the index). PPTX parts are inflated with a 5 MB cap and
scanned without an XML parser, so zip bombs and entity tricks don't apply.

Failures (missing file, damaged or password-protected PDF, unsupported format, indexing
errors) are logged with the speech id and recorded on the `slides.extract` span in Dash0; they
never fail speech creation. Index failures don't roll back stored slides.

The uploaded file lives in the pod's tmp dir and the extraction runs on the pod that received
the upload, so two replicas are fine; a pod restart mid-extraction loses that job (re-upload
to retry). Indexing is a no-op until Elasticsearch is deployed; then set
`config :takeaway, :indexer, Takeaway.Indexer.Elasticsearch`, which calls
`Takeaway.Elasticsearch.index_slide/2` (doc id `<speech_id>_<slide_number>`).

Tests (`test/takeaway/slides_test.exs`, `test/takeaway/slides/extractor_test.exs`) build their
PDF and PPTX files in code. The PDF tests are skipped when `pdftotext` isn't installed
(`apt-get install poppler-utils`, `brew install poppler`).
