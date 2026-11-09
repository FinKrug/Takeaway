# Secrets: this repo and its image are public

Treat any credential that reaches a commit or the image as leaked. Flag as blocking:

- API keys, tokens, passwords, connection strings with credentials, or a kubeconfig anywhere in the diff: code, config, YAML, the Dockerfile, build args, workflow files, tests, fixtures, or docs.
- Secrets passed as a Docker `ARG`/`ENV`, or as `build-args` in `.github/workflows/deploy.yaml`. They end up in the public GHCR image.
- A secret value written into `deploy/*.yaml`. Secrets reach the app only through `valueFrom.secretKeyRef` (for example `app-credentials`, or `db-app` from CloudNativePG). The Secret itself is created on the cluster, outside git.
- New `Secret` manifests under `deploy/`. Argo CD would publish them from this public repo.
- Logging, `IO.inspect`, error messages or telemetry that include a secret, `DATABASE_URL`, `SECRET_KEY_BASE`, or a request's auth headers.

If the PR adds a new secret the app reads, check that it is added to `config/runtime.exs` *and* wired into `deploy/deployment.yaml` via `secretKeyRef`, and that the PR description says which Secret key must exist on the cluster before it deploys.
