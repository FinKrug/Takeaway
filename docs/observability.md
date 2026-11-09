# Observability

| Signal | Where it goes | Source |
|---|---|---|
| Traces | Dash0 over OTLP/HTTP, when `DASH0_AUTH_TOKEN` is set | OpenTelemetry SDK, `app/config/runtime.exs` |
| Logs | Container stdout (read them with Radar's `get_workload_logs` / `get_pod_logs`) | Elixir `Logger` |
| Telemetry metrics | LiveDashboard in dev only (`/dev/dashboard`) | `TakeawayWeb.Telemetry` |
| Container and Kubernetes metrics | In-cluster Prometheus, queried through Radar | cAdvisor, kube-state-metrics |
| Health | `GET /healthz`, `GET /readyz` | `TakeawayWeb.HealthController` |

Operating procedures (what to check after a deploy, how to debug a failure) are in [`AGENTS.md`](../AGENTS.md) and the `ship` and `debug-failure` skills in [`.agents/skills/`](../.agents/skills/).

## OpenTelemetry

### Dependencies (`app/mix.exs`)

`opentelemetry ~> 1.7`, `opentelemetry_api ~> 1.5`, `opentelemetry_exporter ~> 1.11`, `opentelemetry_bandit ~> 0.3`, `opentelemetry_phoenix ~> 2.0`, `opentelemetry_ecto ~> 1.2`.

The release (`releases/0` in `mix.exs`) starts `opentelemetry_exporter` as `:permanent` and `opentelemetry` as `:temporary`: the exporter must start before the SDK, and a crash in the SDK can't take the app down.

### Instrumentation (`app/lib/takeaway/application.ex`)

At boot, before the supervision tree:

```elixir
OpentelemetryBandit.setup()
OpentelemetryPhoenix.setup(adapter: :bandit)
OpentelemetryEcto.setup([:takeaway, :repo], db_statement: :enabled)
```

So every HTTP request (Bandit), Phoenix route and LiveView, and Ecto query gets a span. `db_statement: :enabled` records the SQL text on Ecto spans (parameters are not part of the statement).

### Exporter and resource

`app/config/config.exs` sets the defaults for every environment:

```elixir
config :opentelemetry,
  traces_exporter: :none,
  sampler: {:parent_based, %{root: {Takeaway.OtelSampler, %{}}}},
  resource: %{service: %{name: "takeaway"}}
```

`app/config/runtime.exs` switches on export only when `DASH0_AUTH_TOKEN` is set:

| Setting | Value |
|---|---|
| `traces_exporter` | `:otlp` |
| `otlp_protocol` | `:http_protobuf` |
| `otlp_endpoint` | `DASH0_OTLP_ENDPOINT`, default `https://ingress.us-east-1.aws.dash0.com` |
| Headers | `Authorization: Bearer <token>`, `Dash0-Dataset: <DASH0_DATASET or "default">` |
| `service.name` | `OTEL_SERVICE_NAME`, default `takeaway` |
| `service.version` | `APP_VERSION`, default `dev`. The image bakes in the 7-character commit SHA (`Dockerfile` `ARG APP_VERSION`, passed by `.github/workflows/deploy.yaml`). |

The SDK also reads `OTEL_RESOURCE_ATTRIBUTES`. `deploy/deployment.yaml` sets `deployment.environment.name=hackathon`, `k8s.namespace.name=team-takeaway`, `k8s.deployment.name=app`, and the pod name and UID from the downward API, so Dash0 can tie spans to pods. `deploy-self/app.yaml` sets `deployment.environment.name=self-hosted` for the k3d cluster.

The token lives in Secret `app-credentials`, key `dash0-auth-token`, referenced with `optional: true`: without it the pods start normally and export nothing. Pods only read it at start, so restart the Deployment after adding it. Steps are in the root [README](../README.md#traces-in-dash0).

In Dash0: dataset `default`, service `takeaway`. Filter by `service.version` = the short SHA of a build to compare releases.

In tests, `app/config/test.exs` adds `processors: [{:otel_simple_processor, %{}}]` so tests can attach their own exporter (`app/test/takeaway/otel_sampler_test.exs`).

### Sampler (`app/lib/takeaway/otel_sampler.ex`)

`Takeaway.OtelSampler` is the `root` of a `parent_based` sampler. For a root span it returns `:drop` when the span's `url.path` attribute is `/healthz` or `/readyz`, and `:record_and_sample` otherwise. Child spans follow their parent, so the Ecto or Phoenix spans under a dropped probe request are dropped too. Nothing else is sampled out: every non-probe request is traced. The kubelet's probes (every 5 s readiness, every 10 s liveness, per pod) would otherwise dominate the trace stream.

### Custom spans

One, in `app/lib/takeaway/slides.ex`:

| Span | Attributes | Status |
|---|---|---|
| `slides.extract` | `speech.id`, `artifact.id`; on success `slides.count`, `slides.indexed`, `slides.index_failed`, `slides.empty`; on an unsupported format `slides.skipped = "unsupported_format"` | `error` with the inspected reason when extraction fails |

`Takeaway.Slides.extract_async/1` captures the caller's OpenTelemetry context and attaches it inside the `Task.Supervisor` child, so the background extraction span joins the trace of the upload that started it.

Other background work (transcription, diarization, ES indexing, question tagging and grouping, summaries) has no custom spans; their HTTP calls and Ecto queries show up only where they run inside a traced process (Ecto spans), and their failures are logged.

## Telemetry metrics (`app/lib/takeaway_web/telemetry.ex`)

`TakeawayWeb.Telemetry` is the stock Phoenix module. It starts `:telemetry_poller` every 10 s with no custom periodic measurements and no reporter. `metrics/0` defines summaries for Phoenix endpoint and router dispatch durations, socket and channel timings, `takeaway.repo.query.*` times (total, decode, query, queue, idle), and VM memory and run queues. They are only displayed by LiveDashboard at `/dev/dashboard`, which is mounted when `:dev_routes` is true (dev only). Nothing is exported to Prometheus or Dash0 as metrics, and the app has no `/metrics` endpoint or `prometheus.io/scrape` annotation.

## Health endpoints

`app/lib/takeaway_web/router.ex` routes `GET /healthz` and `GET /readyz` to `TakeawayWeb.HealthController.show/2` outside the `:browser` pipeline (no session, no CSRF). Both return `200 ok`. Neither checks the database or Elasticsearch: readiness means the endpoint is serving. `app/config/prod.exs` excludes both paths from `force_ssl`, because the kubelet calls the pod IP over plain HTTP.

| Probe in `deploy/deployment.yaml` | Path | Period |
|---|---|---|
| readiness | `/readyz` | 5 s |
| liveness | `/healthz` | 10 s |

Liveness must stay cheap and independent of the database (`.gitar/review/phoenix.md`). The other workloads probe `/health` (whisper, diarizer) and `/_cluster/health` / TCP (Elasticsearch); see [deployment.md](deployment.md#manifests-in-deploy).

## Logging

Elixir `Logger` to stdout. Format `$time $metadata[$level] $message` with `request_id` metadata (`Plug.RequestId` in `app/lib/takeaway_web/endpoint.ex`); prod level `:info` (`app/config/prod.exs`), test `:warning`, dev without timestamps or metadata. Background modules prefix their messages with the module, for example `[Elasticsearch.ClusterSetup]`, `[Elasticsearch.Indexer]`, `[Slides]`. Logs are not exported to Dash0. Never log secrets, `DATABASE_URL` or auth headers (`.gitar/review/secrets.md`).

## Checking a running deployment

Brief pointers; the full procedures are in `AGENTS.md` and the skills.

| Question | Tool |
|---|---|
| Are pods healthy, what changed, what's failing? | Radar MCP (`radar-cloud`): `list_resources`, `issues`, `get_changes`, `get_events`, `diagnose`, `get_workload_logs`. Pass the `takeaway` cluster id and `namespace: team-takeaway`. |
| Point-in-time CPU / memory | Radar `top_resources`. |
| Usage over time | Radar `discover_metrics`, then `query_prometheus` with PromQL filtered to `namespace="team-takeaway"`, for example `container_memory_working_set_bytes{namespace="team-takeaway",container="app"}`. Available: `container_*` and `kube_*`. |
| Is the new build serving traffic, and is it slower or failing? | Dash0 MCP (`dash0`): `getSpans` filtered to `service.name = takeaway` and `service.version = <sha7>`, error-status spans for failures, `getTraceDetails`, `getServiceCatalog`. |
| Root cause of an unexplained symptom | Agent0 in Dash0, or a hosted Radar investigation (see `AGENTS.md`). |
