# Deploy gotchas (GitOps to the team's hackathon cluster)

Every push to `main` builds an image and Argo CD deploys `deploy/` to namespace `team-takeaway`. A bad manifest goes straight to the live app at `https://takeaway.cnh.radarhq.io`.

## Never edit by hand

- `images[].newName` / `newTag` in `deploy/kustomization.yaml`. The `build-and-deploy` Action owns them and commits `deploy: <sha> [skip ci]`. A manual change gets overwritten or pins a stale image.

## Things the platform refuses or silently breaks

- **Pods stay `Pending`** if they ask for `privileged`, `hostPath`, `hostNetwork` or `hostPID`. Flag any of these, including in third-party charts or operators.
- **Budget for the whole cluster:** 2 CPU / 4 GiB requests, 4 CPU / 8 GiB limits, 4 PVCs / 20 GiB. Every new container (including init containers and sidecars) needs explicit `resources.requests` and `limits`. Flag replica bumps or new workloads that push the total near the budget, and show the math.
- **Service `app`, port 80, targetPort `http`** is what the public URL routes to. Renaming it, changing its port, or changing the pod label `app: app` takes the site down.
- `type: LoadBalancer` / `NodePort` Services don't work here.
- Leave `deploy/httproute.yaml` alone. It's inert in this cluster but intentional.

## Consistency checks

- A new file in `deploy/` must be listed under `resources:` in `deploy/kustomization.yaml`, or it never deploys.
- The app listens on `PORT` 8080 (`containerPort` named `http`). Probes hit `/healthz` (liveness) and `/readyz` (readiness). If routes or ports change, the probes must change with them.
- The `migrate` init container and the `app` container must get the same `DATABASE_URL` and `SECRET_KEY_BASE` env. A new runtime env var the release needs at boot must be added to both.
- Keep the existing `securityContext` (`runAsNonRoot`, drop `ALL`, `RuntimeDefault` seccomp) on every container. The Dockerfile runs as UID 65534; don't switch it to root.
- If the PR adds an HPA (`examples/hpa`), it must also remove `replicas:` from `deploy/deployment.yaml`, or Argo CD and the autoscaler fight.
- Changes that only touch `**.md` or `deploy/kustomization.yaml` don't trigger a build (`paths-ignore`). A PR that changes app code *and* expects a redeploy must touch something outside those paths.

## Don't touch pre-installed platform pieces

Flag changes that remove or reconfigure Argo CD, Argo Rollouts, Prometheus, the CloudNativePG operator, the metrics setup, the AppProject `team-takeaway`, Secret `default/kubeconfig`, or anything in namespace `radar`. Flag any reference to another team's namespace or the `cnh` cluster.
