# Web layer

This page covers `app/lib/takeaway_web/`: routes, authentication, the LiveViews and
controllers, client-side hooks, the UI kit and the accessibility checks. Paths are relative
to the repo root.

Related pages: [architecture.md](architecture.md) (how the pieces fit),
[domain-model.md](domain-model.md) (schemas such as speeches, events, tickets, plans),
[questions.md](questions.md) (question submission, grouping and tagging),
[pipeline.md](pipeline.md) (audio, transcription, slides, summaries),
[configuration.md](configuration.md), [deployment.md](deployment.md),
[observability.md](observability.md), [development.md](development.md).

## Endpoint and security headers

`app/lib/takeaway_web/endpoint.ex`

| Concern | Setting |
|---|---|
| Session | Signed cookie `_takeaway_key`, `same_site: "Lax"`, not encrypted (contents readable, not tamperable). |
| LiveView socket | `/live`, WebSocket with long-poll fallback; both get the session via `connect_info`. |
| Static files | `Plug.Static` serves `assets fonts images favicon.ico robots.txt` from `priv/static` (`TakeawayWeb.static_paths/0` in `app/lib/takeaway_web.ex`), gzip when code reloading is off. |
| Parsers | urlencoded, multipart, JSON. Then `Plug.MethodOverride`, `Plug.Head`, `Plug.Session`, router. |

Security headers come from `put_secure_browser_headers` in the router's `:browser` pipeline,
with Phoenix's defaults (Phoenix 1.8.16 per `app/mix.lock`); no custom CSP is configured.
CSRF protection is `protect_from_forgery` in the same pipeline, and the LiveView socket sends
the `_csrf_token` read from the `csrf-token` meta tag (`app/assets/js/app.js`,
`app/lib/takeaway_web/components/layouts/root.html.heex`).

**force_ssl.** Set at compile time in `app/config/prod.exs`:

```elixir
force_ssl: [
  rewrite_on: [:x_forwarded_proto],
  exclude: [paths: ["/healthz", "/readyz"], hosts: ["localhost", "127.0.0.1"]]
]
```

The scheme is taken from `X-Forwarded-Proto` (TLS ends at the platform's proxy). Kubernetes
probes hit the pod by IP over plain HTTP, so the probe paths are excluded. Because the option
is compile-time, `app/test/takeaway_web/force_ssl_test.exs` reads `config/prod.exs` and checks
that `/healthz` and `/readyz` are not redirected over HTTP while `/` gets a 301.

## Routes

`app/lib/takeaway_web/router.ex`

Pipelines:

| Pipeline | Plugs |
|---|---|
| `:browser` | `accepts html`, `fetch_session`, `fetch_live_flash`, root layout `Layouts.root`, `protect_from_forgery`, `put_secure_browser_headers`, `fetch_current_organizer` |
| `:attendee` | `TakeawayWeb.AttendeeSession` |
| `:guest_only` | `redirect_if_organizer` (a logged-in organizer goes to `/organizers`) |
| `:organizer_only` | `require_organizer` (others go to `/organizers/log_in`) |

| Method | Path | Handler | Pipelines | Who |
|---|---|---|---|---|
| GET | `/healthz` | `HealthController :show` | none | Kubernetes liveness probe |
| GET | `/readyz` | `HealthController :show` | none | Kubernetes readiness probe |
| GET | `/` | `PageController :home` | browser | anyone |
| GET | `/join` | `PageController :join` | browser | anyone (join-code form target) |
| GET | `/artifacts/:id` | `ArtifactController :show` | browser | anyone (no ownership check, see below) |
| LIVE | `/join/:code` | `SpeechLive.Join` | browser, attendee | attendees; ticket gate if the event uses tickets |
| GET | `/organizers/log_in` | `OrganizerController :new_session` | browser, guest_only | logged-out visitors |
| POST | `/organizers/log_in` | `OrganizerController :create_session` | browser, guest_only | logged-out visitors |
| GET | `/organizers/register` | `OrganizerController :new_registration` | browser, guest_only | logged-out visitors |
| POST | `/organizers/register` | `OrganizerController :create_registration` | browser, guest_only | logged-out visitors |
| DELETE | `/organizers/log_out` | `OrganizerController :delete_session` | browser | anyone (drops the session) |
| GET | `/organizers` | `OrganizerController :dashboard` | browser, organizer_only | logged-in organizer |
| LIVE | `/events/:id/tickets` | `TicketsLive` | browser, organizer_only, live_session `:organizer` | owner of the event |
| LIVE | `/speeches/new` | `SpeechLive.New` | browser, organizer_only, live_session `:organizer` | logged-in organizer |
| LIVE | `/speeches/:code` | `SpeechLive.Show` | browser, organizer_only, live_session `:organizer` | owner of the speech's event |
| LIVE | `/speeches/:id/speak` | `SpeakerLive` | browser, organizer_only, live_session `:organizer` | owner of the speech's event |
| LIVE | `/dev/dashboard` | Phoenix LiveDashboard | browser | only compiled when `:dev_routes` is set |

Note the two speech routes take different keys: `/speeches/:code` is the join code,
`/speeches/:id/speak` is the numeric speech id.

## Authentication and authorization

### Organizers

Accounts: `app/lib/takeaway/organizers.ex`, `app/lib/takeaway/organizers/organizer.ex`.

- **Registration** (`Organizer.registration_changeset/2`): casts `email`, `name`, `password`;
  email is trimmed and downcased, must match `^[^\s@]+@[^\s@]+\.[^\s@]+$`, max 160 chars,
  unique. Password 8 to 72 characters. `password` and `password_hash` are `redact: true`.
- **Hashing** (`Organizers.hash_password/1`): PBKDF2-HMAC-SHA256 via `:crypto.pbkdf2_hmac`,
  16-byte random salt, 32-byte key, stored as `pbkdf2$<iterations>$<b64 salt>$<b64 hash>`.
  Iterations default to 210,000 and can be overridden with `config :takeaway, :pbkdf2_iterations`
  (for example, lower in tests).
- **Login** (`Organizers.authenticate/2`): looks up by normalized email, compares with
  `Plug.Crypto.secure_compare`. For an unknown email it still computes a hash so timing does
  not reveal whether the account exists.

Session handling: `app/lib/takeaway_web/organizer_auth.ex`.

| Function | Kind | Behaviour |
|---|---|---|
| `log_in/2` | helper | Renews the session id, clears the session, stores only `:organizer_id`, redirects to the stored `:organizer_return_to` (if a safe local path) or `/organizers`. |
| `log_out/1` | helper | Drops the session, redirects to `/`. |
| `fetch_current_organizer/2` | plug | Assigns `:current_organizer` (or `nil`) from `:organizer_id`. |
| `require_organizer/2` | plug | Without an organizer: stores the GET path plus query as `:organizer_return_to`, flashes "Log in to continue", redirects to `/organizers/log_in`, halts. |
| `redirect_if_organizer/2` | plug | Sends a logged-in organizer to `/organizers`. |
| `on_mount(:require_organizer, ...)` | LiveView hook | Re-reads `organizer_id` from the session on every mount (including reconnects); assigns `:current_organizer` or halts with a redirect to the login page. |

`safe_path/1` only accepts paths starting with `/`, and rejects `//` prefixes and backslashes,
so the return-to value cannot redirect to another host.

**Ownership.** Being logged in is not enough for the organizer LiveViews; each checks that the
organizer owns the event:

| Page | Check | When it fails |
|---|---|---|
| `TicketsLive` | `Events.get_event_for_organizer/2` (`app/lib/takeaway/events.ex`) | flash "Event not found", navigate to `/` |
| `SpeechLive.Show` | `Organizers.owns_speech?/2` | flash "Speech not found", navigate to `/speeches/new` |
| `SpeakerLive` | `Organizers.owns_speech?/2` at mount, and again in `change_slide/2` on every slide event | flash "Speech not found", redirect to `/` |

Missing and foreign records produce the same response. `owns_event?/2` requires a non-nil
`organizer_id` match, so events without an owner are reachable by nobody.
`SpeechLive.New` has no ownership check: it creates a speech in the organizer's own event
(`SpeechCreator.create_speech/3` with `organizer:`).

### Attendees

`app/lib/takeaway_web/attendee_session.ex`, plug for `/join/:code` only. A LiveView cannot
write the session cookie, so identity is set on the HTTP request before `SpeechLive.Join`
mounts. The attendee is a `users` row with `role: "attendee", anonymous: true`
(`Takeaway.Accounts.create_anonymous_attendee/0`), stored as `"user_id"` in the session and
reused for every speech.

Decision order in `call/2`:

1. Session already has a valid attendee: pass through.
2. User-Agent matches the bot pattern (crawlers, link unfurlers, `curl`, `wget`,
   `headless`, ...): pass through, no user.
3. Unknown join code, or `Tickets.validate_for_event/2` fails for `?ticket=`: pass through,
   no user.
4. Session has `cookie_ok`: create the attendee; if the URL has `cookie_check`, redirect to the
   URL without it.
5. URL has `cookie_check` but no `cookie_ok` came back: cookies are blocked, pass through
   (the page renders read-only).
6. Otherwise set `cookie_ok` and 302 to the same URL plus `cookie_check=1` (other query
   params, such as `ticket`, kept).

The two-step cookie check means rows are only created for clients that keep cookies. Tests:
`app/test/takeaway_web/attendee_session_test.exs`.

## Tickets and billing

### Tickets

`app/lib/takeaway/tickets.ex`, `app/lib/takeaway/tickets/ticket.ex`.

- A ticket belongs to an event and optionally a user. `event_id` and `user_id` are never cast
  from params; only `code` is.
- Codes are 8 characters (`Takeaway.JoinCode`), upper-cased, unique per event
  (`tickets_event_id_code_index`). Generated codes retry up to 5 times on collision, each insert
  in a savepoint.
- `event_uses_tickets?/1`: an event requires tickets as soon as it has issued at least one.
- `validate_for_event/2` returns `:ok` (no tickets on the event, or a matching code),
  `{:error, :ticket_required}` or `{:error, :invalid_ticket}`. Used by both
  `AttendeeSession` and `SpeechLive.Join`.
- `generate_tickets/2`: 1 to 500 unowned tickets in one transaction.
- `import_tickets/2`: one line per attendee, `email` or `email,name`; header lines starting with
  `email` and blank lines are ignored; at most 500 lines. Each email is found or created as an
  attendee user and gets one ticket; existing ticket holders are skipped. Returns
  `%{created, skipped, invalid}`.

Attendees present a ticket as `?ticket=CODE` on the join link.

### Billing and plans

`app/lib/takeaway/billing.ex`, `app/lib/takeaway/billing/plan.ex`.

- A `Plan` has `key` (unique), `name`, `features` (list of strings, `"*"` allows all) and
  `limits` (free-form map, for example `%{"max_speeches" => 5}`).
- An event's plan is set only through `Billing.set_event_plan/2`; `Event.changeset/2` does not
  cast `plan_id`.
- `plan_for_event/1`: the event's plan, else the default plan. `default_plan/0` is the stored
  `"free"` plan, or a built-in plan with `features: ["*"]` if none is stored, so installs
  without billing data keep every feature.
- `feature_allowed?/2`: `nil` plan allows nothing; otherwise `"*"` or the feature name.

What plans gate today: only `:summaries`, via `Takeaway.Summaries.allowed?/1`
(`app/lib/takeaway/summaries.ex`). When it is false, `SpeechLive.Show` shows "Summaries are not
included in your plan" and `SpeechLive.Join` shows "Summaries are not included in this event's
plan". Nothing in `app/lib` reads `limits` yet.

## LiveViews

All LiveViews render inside `Layouts.app` and use `TakeawayWeb, :live_view`. PubSub topics
come from the domain modules:

| Topic | Subscribe with | Messages |
|---|---|---|
| `speech:<id>` | `SpeechCreator.subscribe/1` | `{:speech_started, speech}`, `{:speech_ended, speech}`, `{:slide_changed, speech_id, n}` |
| `speech:<id>:transcript` | `Transcripts.subscribe/1` | `{:transcript_segment, segment}` |
| `speech:<id>:questions` | `Questions.subscribe/1` | `{:question_created, q}`, `{:question_retracted, q}`, `{:question_tagged, q}`, `{:question_answered, q}`, `{:question_groups_updated, speech_id}` |

Subscriptions are made only when `connected?(socket)`.

### SpeechLive.New (`/speeches/new`)

`app/lib/takeaway_web/live/speech_live/new.ex`

- **Mount:** no params. Assigns `page_title`, `form` (`title`, `description`, `tags`).
  Uploads: `:plan` (`.txt .md .pdf .doc .docx`, 1 file, 10 MB) and `:slides`
  (`.pdf .ppt .pptx`, 1 file, 50 MB).
- **Events:** `validate` (re-assigns the form), `save` (blank title adds an error; otherwise
  copies uploaded files out of the upload callback and calls `SpeechCreator.create_speech/3`
  with `organizer:`; on success navigates to `/speeches/<join_code>`), `cancel-upload`.
- **User sees:** title, description, comma-separated tags, two file pickers with progress bars
  and per-file errors ("File too large", "File type not accepted", "Too many files").

### SpeechLive.Show (`/speeches/:code`)

`app/lib/takeaway_web/live/speech_live/show.ex`. The organizer's control page for one speech.

- **Mount params:** `code` (join code). Ownership check as above.
- **Assigns:** `speech`, `artifacts` (`Speeches.list_artifacts/1`), `summary`,
  `summary_locked`, `last_speaker`; streams `segments` (loaded from `started_at` on) and
  `question_groups` (`Questions.list_top_groups/1`, reset on every refresh).
- **Subscribes:** `speech:<id>`, `speech:<id>:transcript`, `speech:<id>:questions`.
- **Events:** `start` (`SpeechCreator.start_speech/1`), `end` (`SpeechCreator.end_speech/1`,
  with a `data-confirm`).
- **PubSub handled:** `:speech_started`, `:speech_ended` (then loads the summary),
  `:transcript_segment`, and `:question_created | :question_retracted |
  :question_groups_updated | :question_tagged | :question_answered` (re-query groups).
- **Async:** `:summary` runs `Summaries.generate_on_end/1` when the speech has ended and no
  speaker summary is cached; `{:error, :plan_required}` sets `summary_locked`.
- **User sees:** title, status badge (Not started, Live, Ended), tags, the join code large
  with the join URL, links to the speaker page, tickets and "Your events", uploaded materials
  (each linking to `/artifacts/:id`), Start or End button, and while live a question
  leaderboard (grouped, most asked first) beside the live transcript. After the end: the
  speech summary with top questions and "When questions spiked" time ranges.

Observation: this view subscribes to `speech:<id>` but has no `handle_info` clause for
`{:slide_changed, id, n}` and no catch-all clause, unlike `SpeakerLive` and `SpeechLive.Join`.
A slide change from the speaker page while this page is open would raise a
`FunctionClauseError` in this LiveView process.

### SpeakerLive (`/speeches/:id/speak`)

`app/lib/takeaway_web/live/speaker_live.ex`. Microphone capture, slide control, transcript
and incoming questions. Uses the wide layout.

- **Mount params:** `id` (numeric speech id). Ownership check as above.
- **Assigns:** `speech`, `recording`, `animate_questions` (false for the initial list so only
  live arrivals animate), `last_speaker`, `slide_count` (`Slides.count_slides/1`),
  `current_slide`; streams `segments` and `questions` (`Questions.list_questions/1`).
- **Subscribes:** transcript, questions and speech topics.
- **Events:**

  | Event | Params | Effect |
  |---|---|---|
  | `audio_chunk` | `data` (base64), `offset_ms`, `content_type` (default `audio/webm`) | Decodes, rejects chunks over 8,000,000 bytes or a negative/non-integer offset, calls `Transcripts.ingest_chunk/4`. Flash on failure. |
  | `recording` | `on` (boolean) | Sets `recording`. |
  | `next_slide` / `prev_slide` | none | Moves the slide by one. |
  | `set_slide` | `slide` | Jumps to a slide; non-integers and out-of-range values are ignored. |

  Slide changes only apply while the speech is live, re-check ownership, and go through
  `SpeechCreator.set_current_slide/3`. If `slide_count` was 0 at mount it is recounted first
  (extraction runs in the background after upload).
- **PubSub handled:** `:transcript_segment`; `:speech_started` / `:speech_ended` (only
  `started_at`/`ended_at` are copied, the local `current_slide` is kept); `:slide_changed`
  (last change wins across tabs and devices); `:question_created` (upsert), `:question_retracted`
  (delete), `:question_tagged` (re-reads the question; skips retracted ones); everything else
  is ignored.
- **User sees:** Start/Stop microphone with a Live badge, the slide position ("Slide n of m",
  `aria-live="polite"`) with Prev/Next, the live transcript with a speaker badge at each change
  of speaker ("Speaker 1", ...), and a questions list tagged by slide or time and marked
  Spoken or Typed.

Public helpers reused by other views: `mark_turns/2`, `insert_segment/2`, `transcript_list/1`
(component), `speaker_name/1`, `format_ms/1`.

### SpeechLive.Join (`/join/:code`)

`app/lib/takeaway_web/live/speech_live/join.ex`. The attendee page.

- **Mount params:** `code`, optional `ticket`. Session: `"user_id"` from `AttendeeSession`.
  `base_assigns/1` sets defaults so the not-found and gated pages render.
- **States:** not found; ticket required; ticket invalid (gated pages never show the speech or
  subscribe); waiting room; live; ended.
- **Assigns (main):** `speech`, `speaker_name`, `user`, `user_id` (only an existing user with
  role `attendee`), `note_form`, `note_status` (`:idle | :saved | :error`), `question_form`,
  `slide_count`, `current_slide`, `question_slide_manual?`, `question_ids`, `my_question_ids`,
  `last_question_at`, `summary`, `summary_locked`, `ticket_error`; streams `questions` (DOM id
  `question-<id>`, entries carry `fresh?` so only live arrivals animate) and `segments`.
- **Events:**

  | Event | Effect |
  |---|---|
  | `save_note` | Autosave of the private note (`Notes.save_note/3`); textarea has `phx-debounce="1000"`. Ignored without a user. |
  | `validate_question` | Re-validates the question form; marks the slide field as manually chosen when the attendee edits it. |
  | `submit_question` | Refused with an inline error if there is no user ("turn on cookies to ask questions"), the speech is not live, or the attendee asked less than 5 s ago. Text required, max 500 chars, slide number > 0. Calls `Questions.submit_question/3` with `slide_source` `"manual"` or `"current"`. |
  | `retract` | `Questions.retract_question_by/2`; only the author can retract (`{:error, :forbidden}` flashes). The button shows only on the attendee's own typed questions. |

- **PubSub handled:** `:speech_started` (also loads captions), `:speech_ended` (loads the
  summary), `:question_created` (upsert), `:question_retracted`, `:question_answered` and
  `:question_tagged` (only for questions already shown), `:slide_changed` (updates the shown
  slide and prefills the form's slide field unless the attendee changed it; clamps to a known
  deck), `:transcript_segment`; anything else is ignored.
- **Async:** `:summary` runs `Summaries.attendee_summary/2` once the speech has ended and the
  attendee has no cached summary.
- **User sees:** title and speaker name; a status region (`role="status"`, `aria-live`); live
  captions while the talk runs (`role="log"`, WCAG 1.2.4); notes and questions as two tabs on
  phones and side by side from `md`; badges on questions (You, Asked aloud, Answered, slide or
  time tag); after the end, "Your cliffnotes" with the attendee's notes. Without a user
  (cookies blocked, crawlers) notes and questions are read-only with an explanation.

### TicketsLive (`/events/:id/tickets`)

`app/lib/takeaway_web/live/tickets_live.ex`

- **Mount params:** `id`. Ownership check via `Events.get_event_for_organizer/2`.
- **Assigns:** `event`, `result`, `ticket_count`, `generate_form` (default count 10),
  `import_form`; stream `tickets`.
- **Events:** `generate` (`Tickets.generate_tickets/2`; non-numbers or values outside 1..500
  flash "Enter a number from 1 to 500"), `import` (`Tickets.import_tickets/2`, then shows
  "Imported N, skipped N existing, N invalid").
- **PubSub:** none.
- **User sees:** a generate form, an import textarea, the running ticket count and every
  ticket code as a badge.

## Controllers

`app/lib/takeaway_web/controllers/`

| Controller | Actions |
|---|---|
| `PageController` | `home` renders `page_html/home.html.heex` (wide layout: hero, join-by-code card, create-speech card, how it works). `join` normalizes `?code=` (upper-case, strip anything not A-Z/0-9, so "abc 234" and "abc-234" both work) and redirects to `/join/<CODE>`; an empty code flashes and redirects to `/#join`. |
| `OrganizerController` | `new_session`/`create_session` (login; failure flashes "Invalid email or password" and re-renders with the email kept), `new_registration`/`create_registration` (logs in on success), `delete_session`, `dashboard` (see "Role home pages" below). Templates are function components in `organizer_html.ex`. |
| `ArtifactController` | `show` sends an uploaded file as a download: looks up the artifact by integer id, takes `Path.basename` of its stored `url` inside `SpeechCreator.uploads_dir/0`, and returns 404 "Not found" if anything is missing. `basename` prevents path traversal. |
| `HealthController` | `show` returns `text/plain` `ok\n` for both probes; no database check. |
| `ErrorHTML`, `ErrorJSON` | Phoenix defaults: status text from the template name (for example "Not Found"); JSON is `{"errors": {"detail": ...}}`. No custom error templates. |

Observation: `/artifacts/:id` is in the plain `:browser` scope with no organizer or ownership
check, so any visitor who knows or guesses an artifact id can download that file. The links
are only rendered on the owner's `SpeechLive.Show` page.

## Role home pages

Each role has one home page that answers "what am I, and what are my talks?". All three
use `TakeawayWeb.SpeechList` (`components/speech_list.ex`): speeches grouped by conference
(event), conferences with a live or upcoming talk first and "Standalone talks" last; inside
a conference, live, then upcoming, then ended. Each row shows a status badge
(`Speech.status/1`: `:live`, `:upcoming`, `:ended`) and the join code, and a summary row
counts each status.

| Page | Who | Lists | Per speech |
|---|---|---|---|
| `/organizers` | organizer | `Speeches.list_speeches_for_organizer/1`: speeches they own plus every speech in their conferences; empty conferences are listed too | speaker (or "No speaker yet"), Manage (`/speeches/:code`), Speaker page; "Manage tickets" per conference |
| `/speaker` | speaker | `Accounts.list_speeches_for_speaker/1` | Open speaker page; a "You're live" card on top for live talks; counts read Live now / To give / Given |
| `/account` | attendee | `Accounts.list_speeches_for_attendee/1` | what they left there (`Accounts.attendee_activity/1`: question count, notes), Open or Review |

The account strip at the top of every page (`#account-nav` in `root.html.heex`, entries
from `Layouts.account_identity/1`) shows a role badge (Organizer, Speaker or Attendee), the
name, a link to that role's home page and its log-out link. An organizer signed in as a
speaker or attendee too gets one entry per role. Logged out, it shows Log in and Sign up.

## JavaScript hooks

| Hook | Defined in | Used by | What it does |
|---|---|---|---|
| `TabList` | `app/assets/js/app.js` | `#attendee-tablist` in `SpeechLive.Join` | WAI-ARIA tablist keyboard support: Left/Up and Right/Down move between tabs (wrapping), Home and End jump to the first/last; clicks and focuses the target tab. The tab switching itself is `Phoenix.LiveView.JS` (`select_tab/1`), client side, toggling `hidden`, `aria-selected` and roving `tabindex`. |
| `.MicStream` | colocated hook in `speaker_live.ex` | `#mic` | `getUserMedia({audio: true})` on the Start button; records 5-second chunks by starting a fresh `MediaRecorder` for each chunk (so every chunk is a standalone, decodable file), base64-encodes them and pushes `audio_chunk` with `offset_ms` and `content_type`. Pushes `recording` on start/stop; stops tracks on destroy. |
| `.SlideKeys` | colocated hook in `speaker_live.ex` | `#slide-keys` | Window `keydown`: ArrowRight/PageDown push `next_slide`, ArrowLeft/PageUp push `prev_slide` (presenter clickers send PageUp/PageDown). Ignored when `data-enabled` is not `"true"`, with modifier keys, or while typing in an input, textarea, select or contenteditable. |

`app.js` merges the colocated hooks (`phoenix-colocated/takeaway`) with `TabList`, sets
`longPollFallbackMs: 2500`, and shows the `topbar` progress bar on `phx:page-loading-start`.

## UI kit

Prose overview: `app/README.md`, "UI kit". Source of truth:
`app/lib/takeaway_web/components/core_components.ex`, `layouts.ex` and `app/assets/css/app.css`.
Tailwind v4, hand-written, no daisyUI.

### Components (`core_components.ex`)

| Component | Attributes / slots |
|---|---|
| `logo/1` | `class` (default `h-8`), `wordmark` (default true; without it the mark gets `role="img"` and `aria-label`). |
| `flash/1` | `kind` `:info` (`role="status"`) or `:error` (`role="alert"`), `title`; full width on phones, toast top right from `sm`; click to dismiss. |
| `button/1` | `variant` `primary` / `secondary` / `ghost` / `danger`; `size` `sm` (h-9) / `md` (h-11) / `lg` (h-13); `class` is appended. Renders a `<.link>` when given `href`, `navigate` or `patch`. `type="submit"` buttons show a spinner during `phx-submit-loading`. |
| `card/1` | `tone` `default` / `sunken` / `brand` / `dashed`, `title` (rendered as `h2`), `:actions` slot. Renders a `<section>`. |
| `header/1` | Page `h1` with `:subtitle` and `:actions` slots. |
| `empty_state/1` | `icon`, `title` (`h2`), body, `:actions`. |
| `badge/1` | `tone` `neutral` / `brand` / `success` / `danger` / `warning` / `outline`; wraps (`break-words`). |
| `live_dot/1` | Pulsing dot in `currentColor`, `aria-hidden`. |
| `spinner/1` | SVG, `motion-safe:animate-spin`, `aria-hidden`. |
| `input/1` | All HTML input types plus `select`, `textarea` (4 rows by default) and `checkbox`; `label`, `hint`, `errors`. Sets `aria-invalid`, `aria-required` and `aria-describedby` (hint and error ids); errors render with `role="alert"`. Errors show only after the field is used (`used_input?`). 16px text on phones to stop iOS zoom. |
| `field_label/1`, `file_input_class/0` | Label and classes for `live_file_input`. |
| `table/1`, `list/1` | Data table (scrolls sideways on narrow screens, supports streams) and description list. |
| `icon/1` | Heroicons by `hero-*` class name, `aria-hidden`. |
| `show/2`, `hide/2` | JS transition helpers. |

### Layouts (`layouts.ex`, `layouts/root.html.heex`)

- `root.html.heex`: `lang="en"`, viewport with `viewport-fit=cover`, light/dark `theme-color`,
  `<.live_title>` with suffix " · Takeaway", and an inline script that sets the theme before
  paint.
- `Layouts.app/1`: skip link (`#skip-link` to `#main`), sticky header with `nav
  aria-label="Main"` (logo, Join, New speech, theme toggle), `<main id="main" tabindex="-1">`,
  footer, and the flash group. Content width `max-w-2xl`, or `max-w-5xl` with `wide` (used by
  the home page, `SpeakerLive` and `SpeechLive.Join` when a speech is found). Safe-area insets
  are respected.
- `flash_group/1` adds `#client-error` and `#server-error` notices shown while the LiveView
  socket is disconnected.
- `theme_toggle/1`: two buttons (`#theme-dark`, `#theme-light`), one visible per theme, that
  dispatch `phx:set-theme`.

### Theme tokens and light/dark (`app/assets/css/app.css`)

Tokens are CSS variables (`--tk-*`, oklch) mapped to Tailwind colors in `@theme inline`:

| Utility names | Purpose |
|---|---|
| `canvas`, `surface`, `sunken` | page, cards, wells and inputs |
| `ink`, `muted` | body and secondary text |
| `line`, `control` | borders; `control` is the input border (3:1 contrast) |
| `brand`, `brand-strong`, `brand-soft`, `on-brand` | tangerine brand, hover, tint, text on brand |
| `success`, `danger`, `warning` and `-soft` | status |
| `font-sans`, `font-display`, `font-mono` | Inter, Inter Display, system mono |
| `animate-enter`, `animate-pop` | 240 ms rise-in and 160 ms scale-in |

Values are defined under `:root, [data-theme="light"]` and `[data-theme="dark"]`. The `dark:`
variant is `[data-theme=dark]`, not the media query. The script in `root.html.heex` reads
`localStorage["phx:theme"]`; without a stored choice it follows `prefers-color-scheme` (and
tracks changes, marked by `data-theme-source="system"`). A toggle click stores the choice;
a `storage` event syncs other tabs.

### Motion

Animations are applied with `motion-safe:` in markup. In addition, a global
`@media (prefers-reduced-motion: reduce)` block sets animation and transition durations to 1 ms,
one iteration, and `scroll-behavior: auto`.

## Accessibility

Work in the code (WCAG references as in the code comments):

- One `h1` per page via `header/1`; cards and empty states use `h2`.
- Skip link first in the tab order; `scroll-padding-top: 5rem` so focused elements are not
  hidden under the sticky header (2.4.11); `:focus-visible` outline in brand.
- `overflow-wrap: break-word` on `body` for reflow at 320 px (1.4.10); buttons at least 24 px
  tall (2.5.8).
- Live regions: attendee status, captions log, note save status, question lists
  (`aria-live="polite"`, `aria-relevant="additions"`), slide position, summary-ready
  announcer (`sr-only`).
- Live captions on the attendee page (1.2.4).
- Unique page titles from `page_title`.

Tests:

| Test | Checks |
|---|---|
| `app/test/takeaway_web/page_structure_test.exs` | Home, login, register and speaker pages: exactly one `header nav[aria-label]`, one `main#main`, one `h1`; the skip link is the first focusable element; titles contain "Takeaway" or the page/speech title and differ between login and register. |
| `app/test/takeaway_web/reflow_motion_test.exs` | The reduced-motion block in `app.css` has the expected rules; `overflow-wrap: break-word` is present; every button size is at least 24 px; spinner uses `motion-safe:animate-spin`; badges don't use `whitespace-nowrap`. |
| `app/test/takeaway_web/theme_contrast_test.exs` | Parses the oklch tokens of both themes, converts to sRGB luminance, and asserts 4.5:1 for text pairs (ink, muted, brand, brand-strong on canvas/surface/sunken; on-brand on brand and brand-strong; ink on brand-soft; each status color on its soft tint, surface and canvas) and 3:1 for `control` borders and brand on surface. |
| `a11y/axe.spec.mjs` | Playwright + `@axe-core/playwright` with tags `wcag2a wcag2aa wcag21a wcag21aa wcag22aa` against `/`, `/join`, `/organizers/log_in`, `/organizers/register`, then registers a throwaway organizer and audits `/organizers` and `/speeches/new`. Any violation fails. |

The axe suite runs in CI through `.github/workflows/a11y.yaml` and locally with
`cd a11y && npm install && npx playwright install chromium && BASE_URL=http://localhost:4000 npm test`
(`a11y/README.md`). Pages that need live state (`/join/:code`, the speaker page) are covered by
`page_structure_test.exs` and the manual VoiceOver checklist in `a11y/README.md`. To add a
page to the axe run, append it to `publicPages` in `axe.spec.mjs`.

Note: `/join` itself is a redirect (to `/#join` with a flash when no code is given), so the
axe check for `/join` audits the home page.
