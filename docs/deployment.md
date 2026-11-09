# Deployment

Takeaway ships by GitOps: a pull request is reviewed by Gitar, merged into `main`, a GitHub Action builds and pushes the image and commits the new tag, and Argo CD in the team's cluster syncs `deploy/`. This page describes the pieces. The step-by-step procedures for agents (and the checks to run after a merge) are in [`AGENTS.md`](../AGENTS.md) and [`.agents/skills/`](../.agents/skills/) (`ship`, `debug-failure`, `canary-release`, `get-started`, `demo-story`); this page doesn't repeat them.

```
branch -> PR -> Gitar review (+ a11y workflow) -> merge to main
  -> build-and-deploy Action: image ghcr.io/finkrug/takeaway:<sha7>, commit "deploy: <sha7> [skip ci]"
  -> Argo CD Application "app" (team-takeaway) syncs deploy/ -> rolling update (migrate init container first)
  -> https://takeaway.cnh.radarhq.io -> Service app:80
```

## Docker image (`Dockerfile`)

The build context is the repo root; the Phoenix project is in `app/`.

| Stage | Base | What it does |
|---|---|---|
| `builder` | `hexpm/elixir:1.20.4-erlang-29.1.1-debian-trixie-20261005-slim` | Installs `build-essential git`, hex and rebar. `MIX_ENV=prod`. Fetches deps, copies `config.exs` + `prod.exs` before `deps.compile` (so compile-time config changes recompile deps), `mix assets.setup`, copies `priv` and `lib`, `mix compile`, copies `assets`, `mix assets.deploy`, then copies `runtime.exs` and `rel/` and runs `mix release`. |
| `final` | `debian:trixie-20261005-slim` | Installs `libstdc++6 openssl libncurses6 locales ca-certificates poppler-utils` (`pdftotext` for `Takeaway.Slides.Pdf`). Sets `en_US.UTF-8`. `ARG APP_VERSION=dev`, `ENV MIX_ENV=prod PORT=8080 APP_VERSION=$APP_VERSION`, `EXPOSE 8080`. Copies the release to `/app`, runs as `USER 65534` (numeric so `runAsNonRoot` can verify it). `CMD ["/app/bin/server"]`. |

No init process (tini) is installed; the comment in the Dockerfile notes where to add one.

`APP_VERSION` is the only build arg; never pass secrets as build args or `ENV` (`.gitar/review/secrets.md`): the GHCR image is public.

### Release overlays (`app/rel/overlays/bin/`)

| Script | Runs |
|---|---|
| `server` | `PHX_SERVER=true exec ./takeaway start`. The image's `CMD`. |
| `server.bat` | Windows equivalent. |
| `migrate` | `./takeaway eval Takeaway.Release.migrate`: runs all pending Ecto migrations for every repo in `:ecto_repos`. Used by the `migrate` init container. |

`Takeaway.Release` (`app/lib/takeaway/release.ex`) also has `rollback/2` and `claim_unowned_events/1` (`bin/takeaway rpc 'Takeaway.Release.claim_unowned_events("me@example.com")'`).

`runtime.exs` raises without `DATABASE_URL` and `SECRET_KEY_BASE` in prod, so the `migrate` container needs both, not just the database URL ([configuration.md](configuration.md)).

## CI workflows (`.github/workflows/`)

### `deploy.yaml` (`build-and-deploy`)

| Aspect | Value |
|---|---|
| Triggers | `push` to `main`, and `workflow_dispatch`. |
| `paths-ignore` | `deploy/kustomization.yaml` and `**.md`. A push changing only those files does not build (this is what keeps the bot's own deploy commit from looping, together with `[skip ci]`). Any other change, including other files under `deploy/` or `deploy-self/`, builds. |
| Concurrency | Group `build-and-deploy`, no cancellation: runs queue. |
| Guard | Skipped when `github.repository == 'skyhook-io/cnh-starter'` (the template). |
| Permissions | `contents: write` (deploy commit), `packages: write` (GHCR). |
| App image | `ghcr.io/<owner/repo lowercased>`, tags `<sha7>` and `latest`, built with `build-args: APP_VERSION=<sha7>`. `sha7` is the first 7 characters of the pushed commit (the merge commit), not the later bot commit. |
| Diarizer image | Built from `diarizer/` into the same GHCR package as tag `diarizer-<sha7>`, only when: the run is manual, the kustomization still says `pending`, the `before` commit is unknown (new branch, force push), or `git diff github.event.before HEAD -- diarizer/` is non-empty. Checkout uses `fetch-depth: 0` for that diff. |
| Deploy commit | Up to 5 attempts: fetch and hard-reset to the latest `origin/main`, `yq` the `app` image (and `diarizer` if built) in `deploy/kustomization.yaml`, commit `deploy: <sha7> [skip ci]` as `github-actions[bot]`, push. Sleeps `3 x attempt` seconds between tries. Rebasing onto the latest main avoids conflicts with pushes that landed during the build. |

After a build-triggering merge, run `git pull --rebase` locally to pick up the deploy commit before your next push.

### `a11y.yaml`

Runs on pull requests touching `app/**`, `a11y/**` or the workflow itself, and manually. It starts `postgres:16`, sets up Elixir 1.20.4 / OTP 29.1.1 and Node 22, runs `mix deps.get`, `mix assets.setup`, `mix setup` with `MIX_ENV=dev`, starts `mix phx.server` in the background and polls `http://localhost:4000/healthz` for up to 2 minutes, then installs Playwright Chromium and runs `npm test` in `a11y/`. Any axe-core violation fails the job. Details in [development.md](development.md#accessibility-suite-a11y).

There is no CI job for `mix test` / `mix precommit`; run them locally before opening a PR.

## Argo CD (`argocd/application.yaml`)

Application `app` in namespace `team-takeaway` (not `argocd`), project `team-takeaway`, source `https://github.com/FinKrug/Takeaway.git` at `main`, path `deploy`, destination namespace `team-takeaway` in the same cluster. `syncPolicy.automated` with `prune: true` and `selfHeal: true`: resources removed from git are deleted, and manual edits on the cluster are reverted. Apply it once (through Radar's `apply_resource`); no `syncOptions` are set. Drive syncs with Radar's `manage_gitops` (procedure in the `ship` skill).

## Manifests in `deploy/`

`deploy/kustomization.yaml` sets `namespace: team-takeaway`, lists the resources below and maps the image names `app` and `diarizer` to `ghcr.io/finkrug/takeaway:<tag>`. The Action owns `newName`/`newTag`; don't edit them by hand (`.gitar/review/deploy.md`). A new file in `deploy/` deploys only if it is listed under `resources:`.

| File | Kind(s) | Summary |
|---|---|---|
| `deployment.yaml` | Deployment `app` | 2 replicas, `RollingUpdate` with `maxSurge: 0`, `maxUnavailable: 1` (a surge pod would exceed the CPU limit quota). Init container `migrate` runs `/app/bin/migrate`; until the database is up it fails and Kubernetes retries while old pods keep serving. Container `app` on port 8080 (`http`). Readiness `GET /readyz` every 5 s, liveness `GET /healthz` every 10 s. Env in [configuration.md](configuration.md). Both containers: `runAsNonRoot`, no privilege escalation, `RuntimeDefault` seccomp, drop `ALL`. No volumes. |
| `service.yaml` | Service `app` | Port 80 -> `http`, selector `app: app`. The platform routes the public URL here: keep the name, port and label. |
| `httproute.yaml` | HTTPRoute `app` | Inert in the vcluster (no Gateway). Argo CD counts it healthy; leave it. |
| `db.yaml` | CNPG Cluster `db` | 1 instance, 1Gi storage. Liveness `isolationCheck` disabled: with a single instance it only restarted Postgres when the API server was slow (card 452). Produces Services `db-rw` etc. and Secret `db-app`. |
| `whisper.yaml` | Deployment + Service `whisper` | `ghcr.io/speaches-ai/speaches:0.9.0-rc.3-cpu`, 1 replica, OpenAI-compatible `/v1/audio/transcriptions` on 8000. Preloads `Systran/faster-whisper-small` (int8, 2 CPU threads, never unloaded) into a 2Gi `emptyDir`, so no PVC. Startup probe allows 6 minutes (36 x 10 s) for the model download. `runAsUser: 1000`. |
| `elasticsearch.yaml` | StatefulSet + headless Service `elasticsearch` | `elasticsearch:8.17.0`, single node, security off, `action.auto_create_index=false`, `node.store.allow_mmap=false` (no privileged sysctl init container), 256 MB heap. `fsGroup: 1000`, `runAsUser: 1000`. 2Gi PVC from `volumeClaimTemplates`. Startup probe allows 5 minutes; readiness `/_cluster/health?wait_for_status=yellow`. No public route. |
| `diarizer.yaml` | Deployment + Service `diarizer` | Image `diarizer` (built from `diarizer/`), 1 replica on purpose (voiceprints live in memory), `Recreate` strategy. Port 8000, `GET /health` startup (2 minutes), readiness and liveness probes. `readOnlyRootFilesystem` with a 64Mi `emptyDir` at `/tmp`. |

### Budget against the cluster quota

The quota covers the whole vcluster: 2 CPU / 4 GiB requests, 4 CPU / 8 GiB limits, 4 PVCs / 20 GiB (`AGENTS.md`, "Limits"). Figures from the manifests above (the CNPG pod uses the `resources` in `db.yaml`). A pod's quota charge is the larger of its init container and the sum of its containers; for `app` both are 100m / 128Mi requests and 500m / 256Mi limits.

| Workload | Pods | CPU req | Mem req | CPU limit | Mem limit | PVC |
|---|---|---|---|---|---|---|
| `app` | 2 | 200m | 256Mi | 1000m | 512Mi | - |
| `db` (CNPG) | 1 | 100m | 256Mi | 500m | 512Mi | 1 x 1Gi |
| `whisper` | 1 | 500m | 1Gi | 1000m | 2Gi | - (2Gi emptyDir) |
| `elasticsearch` | 1 | 250m | 768Mi | 1000m | 1Gi | 1 x 2Gi |
| `diarizer` | 1 | 200m | 384Mi | 300m | 768Mi | - (64Mi emptyDir) |
| **Total** | 6 | **1250m** | **2688Mi (2.63 GiB)** | **3800m** | **4864Mi (4.75 GiB)** | **2 PVCs, 3Gi** |
| Quota | | 2000m | 4096Mi | 4000m | 8192Mi | 4 PVCs, 20Gi |
| Headroom | | 750m | 1408Mi | **200m** | 3328Mi | 2 PVCs, 17Gi |

CPU limits are the tight dimension. That is why `app` rolls with `maxSurge: 0` (a surge pod adds 500m and would stay `Pending` with `exceeded quota`), and why adding a third `app` replica or switching to the 4-replica canary example (`examples/canary/rollout.yaml`, 4 x 500m) does not fit without lowering other limits. These totals exclude anything pre-installed outside `deploy/`; check live usage in Radar before adding workloads.

### Uploads are pod-local

`:uploads_dir` is not configured, so uploaded plans and slide decks go to `/tmp/takeaway_uploads` inside the `app` container (`Takeaway.SpeechCreator.uploads_dir/0`). There is no volume: files are lost when the pod is replaced, and `GET /artifacts/:id` (`TakeawayWeb.ArtifactController`) returns 404 when the request lands on the other replica. Extracted slide text is in Postgres, so it survives. See [pipeline.md](pipeline.md) for slide extraction.

## Self-hosted target (`deploy-self/`)

A second cluster, a k3d cluster on a team member's server (card 460), runs the same app at `take-away.dev`. Its own Argo CD syncs `deploy-self/`; the hackathon cluster keeps syncing `deploy/`. `deploy-self/kustomization.yaml` uses `../deploy` as its base, so image tags come from the same Action commit and every merge to `main` deploys to both.

| Difference | Where | Why |
|---|---|---|
| HTTPRoute deleted | `$patch: delete` in `kustomization.yaml` | k3s has no Gateway API CRDs. |
| Service `app-nodeport` (NodePort 30080) | `app-nodeport.yaml` | k3d publishes it on the server's `127.0.0.1:8180`; Apache on the host proxies the public hostname to it. |
| `app` replicas 1, `maxSurge: 1`, `maxUnavailable: 0` | `app.yaml` | Shared server, no quota. With one replica the hackathon strategy would stop the only pod first (502s during deploys). |
| `PHX_HOST=take-away.dev` | `app.yaml` | LiveView only accepts sockets from this host, so an SSH tunnel on `localhost:8180` no longer gets a live connection. |
| `OTEL_RESOURCE_ATTRIBUTES` with `deployment.environment.name=self-hosted` | `app.yaml` | Separates its traces from the hackathon cluster's in Dash0. |
| `STT_MODEL` and `PRELOAD_MODELS` = `Systran/faster-whisper-base`; whisper 250m / 512Mi requests, 1 CPU / 1Gi limits | `app.yaml`, `whisper.yaml` | About half the memory of `small`; the cluster is capped at 5 GiB. |

The self-hosted cluster still needs Secrets `app-credentials` and (via CNPG) `db-app` created there.

## Examples (`examples/`)

| Directory | What it is | Notes |
|---|---|---|
| `postgres/` | `cluster.yaml` and a README for adding a CNPG Cluster `db`. | Already applied: `deploy/db.yaml` is this file plus the `isolationCheck` override. |
| `canary/` | `rollout.yaml`: Argo Rollouts canary (25%, manual pause, 50% for 60 s, then 100%) and a README. Promote or abort with Radar's `manage_rollout`; procedure in the `canary-release` skill. | Out of date with `deploy/deployment.yaml`: no `migrate` init container, no `DATABASE_URL`, `SECRET_KEY_BASE`, STT, diarizer, ES or Dash0 env, so the release would raise at boot. Uses 4 replicas, which exceeds the CPU-limit budget above. Port the current Deployment spec into a Rollout instead of copying it as is. |
| `agent-workflows/` | Recipes for credentials kept outside git (`app-credentials`), one-off Jobs, adding dependencies and Helm/Argo CD ownership, inspecting the app, confirming a merge is live, hosted AI investigations. | Its "confirm your merge is live" step 4 refers to a `/api/sessions` `version` field from the starter app; Takeaway has no such route. Use the image tag on the live Deployment and Dash0's `service.version` instead (the `ship` skill, steps 5 to 7). |

## `scripts/setup.sh`

Run once in a fresh clone of the hackathon template: `./scripts/setup.sh <team>`. It validates the team name (lowercase, digits, dashes, up to 20 chars), derives `owner/repo` from `git remote get-url origin` (refusing the template repo itself), and replaces `__TEAM__` and `OWNER/REPO` (lowercased for `ghcr.io/...`) in `deploy/`, `argocd/`, `examples/` and `AGENTS.md`. In `deploy/kustomization.yaml` it replaces only `__TEAM__`, leaving the image lines to the Action. It edits files only; it then prints the next steps (commit and push, make the GHCR package public, connect Radar's MCP server). This repo has already been set up for team `takeaway`.

## Gitar review rules (`.gitar/review/`)

Gitar reviews every PR against these files. Summary:

| File | Flags |
|---|---|
| `deploy.md` | Hand edits to image tags; privileged / hostPath / hostNetwork / hostPID pods; containers without requests and limits, or changes that push the budget near the quota (with the math); changes to Service `app` port 80, target `http` or label `app: app`; LoadBalancer / NodePort Services (in `deploy/`); touching `httproute.yaml`; new files missing from `resources:`; probe paths/ports out of sync with routes; `migrate` and `app` env drifting apart; dropping the `securityContext` or running as root; an HPA without removing `replicas:`; changes to pre-installed platform pieces or other teams' namespaces. Notes that `**.md` / kustomization-only PRs don't build. |
| `phoenix.md` | Migrations unsafe for the old code that keeps serving during the rollout (dropping/renaming used columns, `NOT NULL` without default, long backfills, hand-named migrations); required env vars outside `runtime.exs` or not set in `deploy/deployment.yaml`; health endpoints moved into `:browser`, behind auth, or (liveness) depending on the database; `String.to_atom/1` on input, programmatic fields in `cast/3`, interpolated SQL, `dev_routes` exposed, inline `<script>`; missing preloads, lists instead of streams, missing tests, code that fails `mix precommit`. |
| `secrets.md` | Any credential in the diff (code, YAML, Dockerfile, build args, workflows, tests, docs); secrets as Docker `ARG`/`ENV`; secret values in `deploy/*.yaml`; `Secret` manifests under `deploy/`; logging or telemetry that includes a secret, `DATABASE_URL`, `SECRET_KEY_BASE` or auth headers. A new secret must be in `runtime.exs`, wired through `secretKeyRef`, and named in the PR description. |

## Constraints worth remembering

From `AGENTS.md`, verified against the manifests:

- Public URL `https://takeaway.cnh.radarhq.io` routes only to Service `app`, port 80, in `team-takeaway`. No other hostnames, LoadBalancer or NodePort Services.
- The host refuses privileged, hostPath, hostNetwork and hostPID pods; they stay `Pending` with a `SyncError` event. Over-quota pods do the same with `exceeded quota: team-quota`.
- Images must be public on GHCR.
- Change replica counts and config in git: Argo CD self-heal reverts cluster edits.
- Leave the pre-installed Argo CD, Argo Rollouts, Prometheus, CloudNativePG operator, metrics setup, AppProject `team-takeaway`, Secret `default/kubeconfig` and namespace `radar` alone.
