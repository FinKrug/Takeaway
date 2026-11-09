# Development

## Prerequisites

| Tool | Version | Used for |
|---|---|---|
| Elixir / Erlang | 1.20.4 / OTP 29.1.1 (the `Dockerfile` and `a11y.yaml` pin these; `mix.exs` requires `~> 1.17`) | The app |
| Postgres | 16 (CI and `docker-compose.yml`) | Required |
| Elasticsearch | 8.17.0 | Optional: question tagging/grouping and search indexing |
| `pdftotext` (poppler) | any | Optional: PDF slide extraction and its tests (`brew install poppler`, `apt-get install poppler-utils`) |
| Node | 22 | Only for the a11y suite in `a11y/` (assets are built by the esbuild and Tailwind Mix wrappers, not npm) |
| Docker | any | Optional: `docker-compose.yml` |

## Run the app

```bash
cd app
mix setup        # deps.get, ecto.setup (create, migrate, seeds), assets.setup, assets.build
mix phx.server   # http://localhost:4000 (or iex -S mix phx.server)
```

Aliases are in `app/mix.exs`. `mix ecto.reset` drops and re-creates the database. `priv/repo/seeds.exs` creates a "Demo Conference" event (join code `DEMO01`), a speaker and a speech, and is safe to re-run.

Dev config (`app/config/dev.exs`): Postgres `postgres`/`postgres` on `localhost`, database `takeaway_dev`; the endpoint binds `127.0.0.1:4000` with live reload and esbuild/Tailwind watchers; LiveDashboard at `/dev/dashboard`. `dev.exs` sets no Postgres port, so Postgrex's default applies: `PGPORT`, then 5432.

### Postgres and Elasticsearch with Docker Compose

`docker-compose.yml` at the repo root defines three services:

| Service | Image | Port | Notes |
|---|---|---|---|
| `postgres` | `postgres:16-alpine` | 5432 | `postgres`/`postgres`, database `takeaway_dev`: matches `dev.exs`. |
| `elasticsearch` | `elasticsearch:8.17.0` | 9200 | Single node, security off, 512 MB heap. Matches the default `ELASTICSEARCH_URL`. |
| `app` | built from `Dockerfile` | 4000 | The prod release (`bin/server`) with a dev-only `SECRET_KEY_BASE`. |

The usual loop is to run only the backing services and the app on the host:

```bash
docker compose up -d postgres elasticsearch
cd app && mix setup && mix phx.server
```

Caveats for the compose `app` service, from reading the config (it runs in `MIX_ENV=prod`): it does not run migrations (the image's `CMD` is `bin/server`; run `bin/migrate` in the container first), and `PHX_HOST` is unset, so the endpoint's host is `example.com` and LiveView's origin check rejects sockets from `localhost`. Set `PHX_HOST=localhost` if you use it.

### Running without the optional services

Everything outside Postgres is optional, and the app degrades instead of failing:

| Service | Off when | Behavior when off |
|---|---|---|
| Speech-to-text | `STT_URL` unset (default in dev) | `Takeaway.STT.Disabled` logs at debug and returns no segments: the speaker page records audio but no transcript appears. |
| Diarizer | `DIARIZER_URL` unset | `Takeaway.Diarizer.Disabled`: no speaker labels. If it is set but fails, the transcript is still stored without labels. |
| LLM | `ANTHROPIC_API_KEY` unset | `Takeaway.LLM.Disabled` returns `{:error, :disabled}`; summaries use the extractive fallback. |
| Elasticsearch | Not reachable at `ELASTICSEARCH_URL` | `Takeaway.Elasticsearch.ClusterSetup` retries 29 times, 5 s apart, logging warnings, then stops. Indexing failures are logged. Question tagging and grouping fall back to local context and singleton groups. Saved questions are never rejected. |
| Slide extraction | `pdftotext` not installed | PDF extraction fails and is logged; the speech is still created. PPTX extraction needs no external tool. |
| Traces | `DASH0_AUTH_TOKEN` unset | Spans are created but not exported. |

To try the in-cluster services locally (not part of `docker-compose.yml`; untested here), run the same images and point the app at them:

```bash
docker run --rm -p 8000:8000 ghcr.io/speaches-ai/speaches:0.9.0-rc.3-cpu
docker build -t takeaway-diarizer diarizer && docker run --rm -p 8001:8000 takeaway-diarizer

STT_URL=http://localhost:8000/v1/audio/transcriptions \
STT_MODEL=Systran/faster-whisper-small \
DIARIZER_URL=http://localhost:8001/v1/diarize \
mix phx.server
```

Every variable is listed in [configuration.md](configuration.md).

## Tests

```bash
cd app
mix test                                   # creates and migrates takeaway_test first (alias)
mix test test/takeaway/questions_test.exs  # one file
mix test --failed
PGPORT=5433 mix test                       # Postgres on another port
mix test --include elasticsearch test/takeaway/elasticsearch_test.exs   # needs ES on :9200
```

`app/config/test.exs`: database `takeaway_test<MIX_TEST_PARTITION>` with the Ecto SQL sandbox; endpoint on port 4002 with `server: false`; PBKDF2 iterations lowered to 1 000; logger at `:warning`; `:extract_slides`, `:question_grouping` and `:question_tagging` off; ES `auto_setup` and `auto_sync` off; indexer `Takeaway.Indexer.Noop`; an `otel_simple_processor` so tests can capture spans.

### Layout

| Path | Covers |
|---|---|
| `test/support/data_case.ex` | `Takeaway.DataCase`: SQL sandbox (shared mode unless `async: true`), `errors_on/1`. |
| `test/support/conn_case.ex` | `TakeawayWeb.ConnCase`: conn setup plus `organizer_fixture/1` and `log_in_organizer/2`. |
| `test/support/fakes.ex` | Fake implementations of the ports (below). |
| `test/support/slide_fixtures.ex` | Builds PDF and PPTX files in code (`pdf/1`, `pptx/2`, `slide_xml/1`). |
| `test/takeaway/` | Context and worker tests: questions, filter, grouping, tagging, transcripts, diarizer, STT Whisper client, summaries, slides and extractor, Elasticsearch client/indexer/sync/group search, organizers, tickets, billing, domain, OTel sampler. |
| `test/takeaway_web/` | Controllers (health, organizer, page, errors), LiveViews (join, speaker, speech, summary, tickets), components, `force_ssl`, page structure, reduced motion, theme contrast. |

### How fakes are wired

The app talks to external services through behaviours whose implementation comes from app config (`config :takeaway, :stt | :diarizer | :llm | :indexer | :slide_extractor`). Tests replace them per test with `Application.put_env/3` in `setup`, which is why those test modules run `async: false`:

| Fake (`test/support/fakes.ex`) | Replaces | Behavior |
|---|---|---|
| `Takeaway.FakeSTT` | `:stt` | Two segments ("hello", "world"); audio `"boom"` returns `{:error, :down}`. |
| `Takeaway.FakeIndexer` | `:indexer` | Sends `{:indexed, seg}` / `{:indexed_slide, slide}` to `:indexer_test_pid`; slide 2 fails when `:indexer_fail_slide_2` is set. |
| `Takeaway.FakeSlideExtractor` | `:slide_extractor` | Three slides; files named `missing*` return `{:error, :enoent}`, `boom*` raise. Notifies `:extractor_test_pid`. |
| `Takeaway.FakeLLM` / `Takeaway.FailingLLM` | `:llm` | Echoes `"AI: ..."` and notifies `:llm_test_pid` / always `{:error, :down}`. |
| `Takeaway.FakeDiarizer` | `:diarizer` | Two speaker turns; `:fake_diarizer_mode` `:error` or `:raise` simulate failure. |

Elasticsearch tests don't need a server: they set `request_options: [plug: {Req.Test, __MODULE__}]` under `config :takeaway, :elasticsearch` and stub responses with `Req.Test.stub/2`, restoring the old config in `on_exit`. `Takeaway.Diarizer.HTTP` takes `req_options` the same way. `:question_filter` is overridden with an inline function in `questions_test.exs` and `join_live_test.exs`.

### Tags and skips

- `:elasticsearch`: excluded by default (`test/test_helper.exs`: `ExUnit.start(exclude: [:elasticsearch])`). The "live elasticsearch operations" block in `test/takeaway/elasticsearch_test.exs` creates uniquely named indices on a real ES.
- PDF tests in `test/takeaway/slides/extractor_test.exs` and `test/takeaway/slides_test.exs` are skipped with "pdftotext not installed" when `Takeaway.Slides.Pdf.available?/0` is false.
- `:tmp_dir` is used by the extractor tests for scratch files.

## `mix precommit`

Runs in the `test` env (`cli/0` in `mix.exs`): `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`. Run it before every PR; Gitar flags code that fails it, and no CI job runs the Elixir tests. Formatting config is `app/.formatter.exs` (with `Phoenix.LiveView.HTMLFormatter` for HEEx).

## Accessibility suite (`a11y/`)

`a11y/axe.spec.mjs` runs axe-core (`@axe-core/playwright` 4.10.2, Playwright 1.49.1) with the WCAG 2.0/2.1/2.2 A and AA tags against `/`, `/join`, `/organizers/log_in`, `/organizers/register`, then registers a throwaway organizer and checks `/organizers` and `/speeches/new`. Any violation fails. CI runs it on PRs touching `app/` or `a11y/` ([deployment.md](deployment.md#a11yyaml)).

```bash
cd app && mix phx.server         # in one shell
cd a11y && npm install && npx playwright install chromium
BASE_URL=http://localhost:4000 npm test
```

Pages that need live state (`/join/:code`, the speaker view) are covered by `app/test/takeaway_web/page_structure_test.exs` and the manual VoiceOver checklist in `a11y/README.md`. Add a page by appending to `publicPages` in `axe.spec.mjs`.

## Coding conventions

`app/AGENTS.md` is the full guide (Phoenix 1.8 / LiveView usage rules plus project rules). The points that matter most here:

- **HTTP:** use `Req`. (Two older clients, `Takeaway.STT.Whisper` and `Takeaway.LLM.Anthropic`, still use `:httpc`.)
- **UI:** build from `core_components.ex` (`<.button>`, `<.card>`, `<.header>`, `<.input>`, `<.badge>`, `<.empty_state>`, ...) and the theme tokens in `assets/css/app.css`. No raw Tailwind colors, no daisyUI, mobile first. Every LiveView template starts with `<Layouts.app flash={@flash}>`; icons via `<.icon>`. See the UI kit in `app/README.md` and [web.md](web.md).
- **JS/CSS:** only the `app.js` / `app.css` bundles; no inline `<script>` in HEEx (use colocated or external hooks with a unique DOM id); Tailwind v4 import syntax in `app.css`; no `@apply`.
- **Elixir:** no index access on lists (`Enum.at/2`); bind the result of `if`/`case`; one module per file; no map access on structs; no `String.to_atom/1` on user input; predicates end in `?`, not `is_`.
- **Ecto:** preload associations used in templates; don't `cast` programmatically set fields (owner ids, roles); generate migrations with `mix ecto.gen.migration`; migrations must be safe for the old code still serving during a rollout (`.gitar/review/phoenix.md`).
- **LiveView:** streams for collections; `<.link navigate/patch>` and `push_navigate`/`push_patch`; forms via `to_form/2` and `<.form for={@form}>`; no LiveComponents without a strong reason.
- **Tests:** `start_supervised!/1` for processes; no `Process.sleep/1` (monitor and `assert_receive`, or `:sys.get_state/1`); LiveView tests select by element id with `has_element?/2`, not raw HTML; new controllers and LiveViews need tests.
- **Config:** new env vars go in `config/runtime.exs`, must be wired in `deploy/deployment.yaml` (both containers if needed at boot), and secrets only via `secretKeyRef` ([configuration.md](configuration.md)).

## Branches and pull requests

Every change reaches `main` through a pull request, never a direct push: Gitar reviews it (rules in `.gitar/review/`, summarized in [deployment.md](deployment.md#gitar-review-rules-gitarreview)). Work on a branch, run `mix precommit`, push the branch and open a PR with `gh pr create`. Fix Gitar's findings on the same branch or reply on the PR where you disagree; merge only when the change's owner says so. Merging to `main` builds and deploys; afterwards `git pull --rebase` to pick up the bot's `deploy: <sha> [skip ci]` commit.

The team tracks work on the Hackathon task board; agents follow the board rules and the `ship` procedure in [`AGENTS.md`](../AGENTS.md) and [`.agents/skills/ship/`](../.agents/skills/ship/).
