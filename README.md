# Takeaway

Live companion for conference talks. A speaker starts a speech and shares a join code; attendees follow a live transcript, ask questions and take notes from their phones. When the speech ends, Takeaway writes a summary for the speaker (what was covered, the top questions, when questions spiked) and a personal cheat sheet for each attendee that merges the talk with their own notes.

Built for the [Cloud Native Hackathon](https://www.wemakedevs.org/hackathons/cnh) (Radar AI SRE track). Live at **https://takeaway.cnh.radarhq.io**.

## How it works

| Route | Who | What |
|---|---|---|
| `/speeches/new` | Speaker | Create a speech, upload a plan/transcript and slides. |
| `/speeches/:code` | Speaker | Start/end the speech, join link and code, questions, post-speech summary. |
| `/speeches/:id/speak` | Speaker | Captures mic audio and shows the live transcript. |
| `/join/:code` | Attendee | Live transcript, ask/retract questions, notes, personal summary afterwards. |
| `/healthz`, `/readyz` | Kubernetes | Probes. |

- **Stack:** Elixir / Phoenix LiveView, Postgres (CloudNativePG), PubSub for live updates.
- **Speech-to-text** (`Takeaway.STT`): audio chunks go to any OpenAI-compatible `/audio/transcriptions` endpoint; segments are stored with timestamps on the speech's transcript. Without `STT_URL` no segments are produced.
- **Summaries** (`Takeaway.Summaries`, `Takeaway.LLM`): generated once when the speaker presses **End Speech** and cached in `summaries`. With `ANTHROPIC_API_KEY` Claude writes them; otherwise (or if the call fails) an extractive fallback is stored.

Main code lives in `app/lib/takeaway/` (contexts: `speeches`, `questions`, `notes`, `transcripts`, `summaries`, `accounts`, `events`) and `app/lib/takeaway_web/live/` (LiveViews).

## Configuration

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | Postgres URL (from Secret `db-app` in the cluster). |
| `SECRET_KEY_BASE` | Phoenix cookie signing (Secret `app-credentials`). |
| `PHX_HOST`, `PORT` | Public host and listen port (8080 in the image). |
| `STT_URL`, `STT_API_KEY`, `STT_MODEL` | Speech-to-text endpoint (default model `whisper-1`). |
| `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL` | Claude for summaries (optional). |
| `POOL_SIZE` | Ecto pool size. |
| `DASH0_AUTH_TOKEN`, `DASH0_OTLP_ENDPOINT`, `DASH0_DATASET` | OpenTelemetry traces to Dash0 (off without a token; defaults US East, dataset `default`). |

Secrets live in Kubernetes Secrets created outside git (see [`examples/agent-workflows`](examples/agent-workflows/README.md)); only their names go in `deploy/`. The repo and image are public: never commit a key.

### Traces in Dash0

The app sends OpenTelemetry traces (HTTP requests, Phoenix routes and LiveViews, Ecto queries) to Dash0. Tracing stays off until the pods have a token, and probe requests (`/healthz`, `/readyz`) are never traced.

1. In Dash0, open **Settings** > **Auth Tokens** and create a token that can ingest data.
2. Add it as key `dash0-auth-token` to the existing Secret `app-credentials` in `team-takeaway` (add the key; don't replace the Secret, which also holds `secret-key-base`). In Radar Cloud: **Resources** > **Secrets** > `app-credentials`, add it under `stringData`, **Apply**.
3. Restart the app (`manage_workload` in Radar) so the pods read it. The service `takeaway` appears in Dash0's **Services** within a minute.

## Local development

You need Elixir/Erlang and a local Postgres.

```bash
cd app
mix setup          # deps, database, assets
mix phx.server     # http://localhost:4000
mix test
```

## Deploy

GitOps through Argo CD in the team's vcluster (`takeaway`, namespace `team-takeaway`):

1. Push to `main`. The `build-and-deploy` GitHub Action builds the image from `Dockerfile`, pushes it to `ghcr.io/finkrug/takeaway` and commits `deploy: <sha> [skip ci]`, updating the tag in `deploy/kustomization.yaml`.
2. Argo CD (Application `app` in `team-takeaway`) syncs `deploy/`: the Deployment (with a `bin/migrate` init container), Service `app`, the Postgres `Cluster` (`db.yaml`) and an HTTPRoute.
3. The platform routes `https://takeaway.cnh.radarhq.io` to Service `app`, port 80.

Observe and operate it with [Radar Cloud](https://app.radarhq.io) and its MCP server. Coding agents: read [`AGENTS.md`](AGENTS.md) and the skills in `.agents/skills/` (`ship`, `debug-failure`, `canary-release`, `demo-story`, `get-started`).

### Cluster limits

2 CPU / 4 GiB requests, 4 CPU / 8 GiB limits, 4 PVCs / 20 GiB across the whole cluster. No privileged, hostPath, hostNetwork or hostPID pods; no LoadBalancer or NodePort Services. A pod over budget stays `Pending` with a `SyncError` event.

## Repo layout

```
app/              Phoenix application
deploy/           Kustomize manifests Argo CD syncs
argocd/           The Argo CD Application (applied once)
examples/         Postgres, canary rollout and agent-workflow recipes
scripts/setup.sh  Points a fresh clone at a team
.agents/skills/   Agent procedures (ship, debug, canary, demo story)
```

## Team

Nathan, Francisco and Finley. Work is tracked on the Hackathon task board.
