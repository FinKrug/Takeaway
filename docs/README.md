# Takeaway developer docs

Takeaway is a live companion for conference talks. A speaker starts a speech and shares a join code; attendees follow a live transcript, ask questions and take notes from their phones. When the speech ends, Takeaway writes a summary for the speaker and a personal cheat sheet for each attendee.

The [root README](../README.md) is the quick tour. These pages go deeper, and each one points at the code it describes.

## Start here

| Page | Read it when you want to know |
|---|---|
| [Architecture](architecture.md) | What the moving parts are, how they connect, the supervision tree, PubSub topics and background work. |
| [Domain model](domain-model.md) | Every table and schema, the context APIs, and the migration history. |
| [Development](development.md) | How to run the app and its tests locally, with or without the optional services. |

## How features work

| Page | Covers |
|---|---|
| [Speech pipeline](pipeline.md) | Mic capture, speech-to-text (Whisper), speaker labels (diarizer), transcripts, slide extraction, post-speech summaries. |
| [Questions](questions.md) | Submission and filtering, context tags, background tagging and grouping, and the Elasticsearch index behind them. |
| [Web layer](web.md) | Routes, organizer and attendee auth, tickets and plans, each LiveView, JS hooks, the UI kit and accessibility. |

## Running it

| Page | Covers |
|---|---|
| [Configuration](configuration.md) | Every environment variable and `config :takeaway` key, with defaults and the Secret that supplies it. |
| [Deployment](deployment.md) | Docker image, CI, Argo CD, the manifests in `deploy/` against the cluster budget, and the self-hosted `deploy-self/` target. |
| [Observability](observability.md) | OpenTelemetry traces to Dash0, sampling, custom spans, metrics, health probes. |

## For coding agents

Agent procedures (shipping, debugging, canary releases, the demo story) live in [`AGENTS.md`](../AGENTS.md) and [`.agents/skills/`](../.agents/skills/). App coding conventions are in [`app/AGENTS.md`](../app/AGENTS.md). These docs describe the system; those files describe how to operate on it.
