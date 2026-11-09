# Configuration

Takeaway is configured in two layers:

1. **Environment variables**, read at boot by `app/config/runtime.exs` (runs in every environment, including the release). A few are also read by the OpenTelemetry SDK, Postgrex, the Mix test config and the release scripts.
2. **`config :takeaway, ...` keys**, set in `app/config/*.exs` and read with `Application.get_env/2` in `app/lib`. Most of them select an implementation module (a "port") or toggle background work. Tests swap them with `Application.put_env/3` (see [development.md](development.md#how-fakes-are-wired)).

Compile-time config (`config.exs`, `dev.exs`, `prod.exs`, `test.exs`) is baked into the image; anything that must change per deployment belongs in `runtime.exs` (rule in `.gitar/review/phoenix.md`).

## Environment variables

### Read by the app (`app/config/runtime.exs` unless noted)

| Variable | Default | Env | Effect | Supplied in `deploy/` by |
|---|---|---|---|---|
| `PHX_SERVER` | unset | all | Any value sets `server: true` on the endpoint. `app/rel/overlays/bin/server` sets it to `true` before `takeaway start`. | `bin/server` (the image's `CMD`) |
| `PORT` | `4000` | all | HTTP listen port. The image sets `PORT=8080` (`Dockerfile`). | Image default `8080` |
| `DATABASE_URL` | none: **raises** if missing | prod | Ecto URL for `Takeaway.Repo`. | Secret `db-app`, key `uri` (made by CloudNativePG for Cluster `db`), on both the `migrate` init container and `app` |
| `POOL_SIZE` | `10` | prod | Ecto pool size. | Literal `"5"` |
| `ECTO_IPV6` | unset | prod | `true` or `1` adds `:inet6` to the DB socket options. | Not set |
| `SECRET_KEY_BASE` | none: **raises** if missing | prod | Signs cookies and LiveView tokens. | Secret `app-credentials`, key `secret-key-base` (created outside git), on both containers |
| `PHX_HOST` | `example.com` | prod | Public host for generated URLs (`https`, port 443). LiveView's origin check uses it, so a wrong value breaks live sockets. | Literal `takeaway.cnh.radarhq.io` (`deploy-self/`: `take-away.dev`) |
| `DNS_CLUSTER_QUERY` | unset (`:ignore`) | prod | DNS query for `DNSCluster` node discovery (`app/lib/takeaway/application.ex`). | Not set: pods do not form an Erlang cluster |
| `ELASTICSEARCH_URL` | `http://localhost:9200` | all | Base URL for `Takeaway.Elasticsearch.client/0`. | Literal `http://elasticsearch:9200` |
| `ELASTICSEARCH_API_KEY` | unset | all | Sent as `Authorization: ApiKey ...` when non-empty. | Not set (in-cluster ES has security off) |
| `STT_URL` | unset | all | When set, selects `Takeaway.STT.Whisper` and points it at an OpenAI-compatible `/audio/transcriptions` endpoint. Unset: `Takeaway.STT.Disabled` drops audio (no segments). | Literal `http://whisper:8000/v1/audio/transcriptions` |
| `STT_API_KEY` | unset | all | Bearer token for `STT_URL`. | Not set (Speaches is open inside the cluster) |
| `STT_MODEL` | `whisper-1` | all | `model` form field sent to the STT endpoint. | Literal `Systran/faster-whisper-small` (`deploy-self/`: `Systran/faster-whisper-base`) |
| `STT_DIARIZE` | off | all | `true`/`1`/`yes`/`on` (case-insensitive) asks the STT provider for speaker labels. Speaches and `whisper-1` do not support it. | Not set |
| `DIARIZER_URL` | unset | all | When set, selects `Takeaway.Diarizer.HTTP` and points it at the diarizer's `/v1/diarize`. Unset: `Takeaway.Diarizer.Disabled` (no speaker labels). | Literal `http://diarizer:8000/v1/diarize` |
| `ANTHROPIC_API_KEY` | unset | all | When set, selects `Takeaway.LLM.Anthropic` for summaries. Unset: `Takeaway.LLM.Disabled`, callers store an extractive summary. | **Not wired in `deploy/`**: the cluster runs with extractive summaries |
| `ANTHROPIC_MODEL` | `claude-sonnet-4-5` | all | Model for `Takeaway.LLM.Anthropic`. | Not set |
| `DASH0_AUTH_TOKEN` | unset | all | When set, turns on the OTLP trace exporter (see [observability.md](observability.md)). Unset: no traces leave the pod. | Secret `app-credentials`, key `dash0-auth-token`, `optional: true` (app container only) |
| `DASH0_OTLP_ENDPOINT` | `https://ingress.us-east-1.aws.dash0.com` | all | OTLP/HTTP endpoint. Only read when the token is set. | Not set |
| `DASH0_DATASET` | `default` | all | `Dash0-Dataset` header. Only read when the token is set. | Not set |
| `OTEL_SERVICE_NAME` | `takeaway` | all | `service.name` resource attribute. Only read in `runtime.exs` when the token is set. | Literal `takeaway` |
| `APP_VERSION` | `dev` | all | `service.version` resource attribute. Only read when the token is set. | Baked into the image: `ARG APP_VERSION` in `Dockerfile`, passed by the Action as the 7-char commit SHA |
| `OTEL_RESOURCE_ATTRIBUTES` | unset | all | Read by the OpenTelemetry SDK itself (not by app code): extra resource attributes. | Literal: `deployment.environment.name=hackathon`, `k8s.namespace.name`, `k8s.deployment.name`, `k8s.pod.name`, `k8s.pod.uid` (the last two from `K8S_POD_NAME` / `K8S_POD_UID`, set from the downward API) |
| `PGPORT` | `5432` | test (dev via Postgrex) | `app/config/test.exs` reads it for the test repo port. `dev.exs` sets no port, so Postgrex's own default applies, which also reads `PGPORT`. | n/a |
| `MIX_TEST_PARTITION` | empty | test | Suffix on the test database name (`takeaway_test<N>`). | n/a |

### Set in `deploy/` but not read by the app

| Variable | Where | Note |
|---|---|---|
| `TEAM_NAME` | `deploy/deployment.yaml`, `examples/canary/rollout.yaml` | Left over from the platform's starter app. Nothing in `app/` reads it. |
| `K8S_POD_NAME`, `K8S_POD_UID` | `deploy/deployment.yaml` | Only used to expand `OTEL_RESOURCE_ATTRIBUTES`. |

### Other workloads

| Workload | Variable | Value in `deploy/` | Default in code | Effect |
|---|---|---|---|---|
| `diarizer` (`diarizer/server.py`) | `MATCH_THRESHOLD` | `0.7` | `0.7` | Cosine similarity a chunk's speaker needs to match a known voiceprint. Raise if two people share a label; lower if one person gets several. |
| | `NUM_THREADS` | `1` | `1` | sherpa-onnx threads. |
| | `CLUSTER_THRESHOLD` | not set | `0.3` | Clustering threshold inside one chunk. |
| | `MIN_EMBED_SECONDS` | not set | `0.8` | Minimum speech length for an embedding. |
| | `MAX_SESSIONS` | not set | `200` | Voiceprint sessions kept in memory. |
| | `SESSION_TTL_SECONDS` | not set | `21600` (6 h) | Session expiry. |
| | `MODEL_DIR` | image: `/models` | `/models` | Baked-in ONNX models. |
| `whisper` (Speaches) | `WHISPER__INFERENCE_DEVICE`, `WHISPER__COMPUTE_TYPE`, `WHISPER__CPU_THREADS`, `STT_MODEL_TTL`, `PRELOAD_MODELS`, `ENABLE_UI`, `LOG_LEVEL`, `HF_HOME` | `cpu`, `int8`, `2`, `-1`, `["Systran/faster-whisper-small"]`, `false`, `info`, `/home/ubuntu/.cache/huggingface` | Speaches' own | See `deploy/whisper.yaml` comments. |
| `elasticsearch` | `discovery.type`, `xpack.security.enabled`, `action.auto_create_index`, `node.store.allow_mmap`, `ES_JAVA_OPTS` | `single-node`, `false`, `false`, `false`, `-Xms256m -Xmx256m` | ES's own | `auto_create_index=false` means only `Takeaway.Elasticsearch.ClusterSetup` creates indices, with explicit mappings. |

## Kubernetes Secrets

Neither Secret is in git (the repo and image are public; `.gitar/review/secrets.md` blocks any Secret manifest under `deploy/`).

| Secret | Created by | Keys used | Consumers |
|---|---|---|---|
| `db-app` | CloudNativePG operator, for Cluster `db` (`deploy/db.yaml`) | `uri` (also has `username`, `password`, `host`, `port`, `dbname`) | `DATABASE_URL` on `migrate` and `app` |
| `app-credentials` | A person, through Radar's resource editor (`examples/agent-workflows/README.md`) | `secret-key-base` (required), `dash0-auth-token` (optional) | `SECRET_KEY_BASE` on `migrate` and `app`; `DASH0_AUTH_TOKEN` on `app` |

Pods read env from Secrets only at start: after changing `app-credentials`, restart the Deployment (`manage_workload` in Radar).

## `config :takeaway` keys

| Key | Set in | Default when unset | Read in | Effect |
|---|---|---|---|---|
| `:env` | `config.exs` (`config_env()`) | - | `elasticsearch/cluster_setup.ex`, `elasticsearch/question_sync.ex` | `:test` turns off ES auto-setup, auto-sync and setup retries unless overridden. |
| `:ecto_repos` | `config.exs` | - | `release.ex` | Repos migrated by `bin/migrate`. |
| `:dev_routes` | `dev.exs` (`true`) | off | `takeaway_web/router.ex` (`compile_env`) | Mounts LiveDashboard at `/dev/dashboard`. |
| `:dns_cluster_query` | `runtime.exs` (prod, from `DNS_CLUSTER_QUERY`) | `:ignore` | `application.ex` | `DNSCluster` query. |
| `:elasticsearch` | `config.exs`, `runtime.exs`, `test.exs` | `[]` | `elasticsearch.ex`, `cluster_setup.ex`, `question_sync.ex` | Keyword list: `url` (default `http://localhost:9200`), `api_key`, `auto_setup` (create indices at boot; default `env != :test`), `auto_sync` (subscribe to question events and mirror them to ES; default `env != :test`), `request_options` (merged into the `Req` client; tests use `plug: {Req.Test, ...}`). `test.exs` sets `auto_setup: false, auto_sync: false`. |
| `:indexer` | `config.exs` (`Takeaway.Elasticsearch.Indexer`), `test.exs` (`Takeaway.Indexer.Noop`) | `Takeaway.Indexer.Noop` | `indexer.ex` | Where transcript segments and slides are sent for indexing. |
| `:stt` | `runtime.exs` when `STT_URL` is set | `Takeaway.STT.Disabled` | `stt.ex` | Speech-to-text implementation. |
| `Takeaway.STT.Whisper` | `runtime.exs` | `[]` (`url` required) | `stt/whisper.ex` | `url`, `api_key`, `model` (default `whisper-1`), `diarize` (default `false`). Per-call `opts` override `url`, `model`, `diarize`. |
| `:diarizer` | `runtime.exs` when `DIARIZER_URL` is set | `Takeaway.Diarizer.Disabled` | `diarizer.ex` | Speaker-label implementation. |
| `Takeaway.Diarizer.HTTP` | `runtime.exs` | `[]` (`url` required) | `diarizer.ex` | `url`, `timeout` (receive timeout, default 15 000 ms), `req_options` (merged into `Req`, used by tests). |
| `:llm` | `runtime.exs` when `ANTHROPIC_API_KEY` is set | `Takeaway.LLM.Disabled` | `llm.ex` | Summary text generator. |
| `Takeaway.LLM.Anthropic` | `runtime.exs` | `[]` (`api_key` required) | `llm/anthropic.ex` | `api_key`, `model` (default `claude-sonnet-4-5`). 60 s HTTP timeout, `max_tokens` 1024 unless passed per call. |
| `:question_filter` | not set anywhere | `Takeaway.Questions.Filter.filter/1` | `questions.ex` (`filter_text/1`) | A 1-arity function or `{module, function}` returning `{:ok, text}` / `{:error, reason}`, run before a question is saved. See [questions.md](questions.md). |
| `:question_tagging` | `test.exs` (`false`) | `true` | `questions/tag_worker.ex` | When false, `Takeaway.Questions.TagWorker` does not subscribe, so no background context-tag enrichment. Its `:enabled` start option overrides. |
| `:question_grouping` | `test.exs` (`false`) | `true` | `questions/group_worker.ex`, `summaries.ex` | When false, `GroupWorker` does not subscribe and speaker summaries skip `Grouping.assign_pending/1` before they are generated. |
| `:question_group_similarity` | not set anywhere | `0.6` (`@threshold` in `questions/grouping.ex`) | `questions/grouping.ex` | Minimum content-word Jaccard similarity for two questions to share a group. |
| `:extract_slides` | `test.exs` (`false`) | `true` | `slides.ex` (`extract_async/1`) | Background slide text extraction after upload. |
| `:slide_extractor` | not set (tests set `Takeaway.FakeSlideExtractor`) | `Takeaway.Slides.Extractor.Default` | `slides/extractor.ex` | Slide text extractor (pdftotext / PPTX). |
| `:uploads_dir` | not set anywhere | `System.tmp_dir!()/takeaway_uploads` | `speech_creator.ex`, `slides.ex`, `artifact_controller.ex` | Where uploaded plans and slides are stored. In the cluster this is the container's `/tmp`, see [deployment.md](deployment.md#uploads-are-pod-local). |
| `:pbkdf2_iterations` | `test.exs` (`1_000`) | `210_000` | `organizers.ex` | PBKDF2-SHA256 iterations for organizer passwords. |
| `:generators` | `config.exs` | - | Phoenix generators | `timestamp_type: :utc_datetime`. |

Test-only keys read by the fakes in `app/test/support/fakes.ex`: `:indexer_test_pid`, `:llm_test_pid`, `:extractor_test_pid`, `:indexer_fail_slide_2`, `:fake_diarizer_mode`.

## Other application config

| App / key | Set in | Value |
|---|---|---|
| `TakeawayWeb.Endpoint` | `config.exs`, `dev.exs`, `test.exs`, `prod.exs`, `runtime.exs` | Bandit adapter. Dev binds `127.0.0.1:4000` with code reload and esbuild/tailwind watchers. Test binds `127.0.0.1:4002`, `server: false`. Prod: `force_ssl` with `rewrite_on: [:x_forwarded_proto]`, excluding `/healthz`, `/readyz` and hosts `localhost`, `127.0.0.1` (`prod.exs`); binds all IPv6/IPv4 interfaces; `cache_static_manifest`. |
| `:opentelemetry` | `config.exs`, `test.exs`, `runtime.exs` | See [observability.md](observability.md). |
| `:logger` | `config.exs`, `dev.exs`, `test.exs`, `prod.exs` | Format `$time $metadata[$level] $message` with `request_id` metadata; dev drops metadata and timestamps; test level `:warning`; prod level `:info`. |
| `:esbuild` / `:tailwind` | `config.exs` | esbuild 0.25.4, Tailwind 4.3.3. |
| `Takeaway.Repo` | `dev.exs`, `test.exs`, `runtime.exs` | Dev: `postgres`/`postgres`@`localhost`, db `takeaway_dev`, pool 10. Test: same credentials, `PGPORT`, db `takeaway_test<partition>`, SQL sandbox, pool `2 x schedulers`. |
