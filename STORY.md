# Takeaway — Cloud Native Hackathon Demo Story

## Before

- Morning cluster setup on Radar Cloud (`takeaway`, cluster ID `vyg02svjQsw`, namespace `team-takeaway`) started from the hackathon starter template before custom CloudNativePG migrations, Elasticsearch slide indexing, OpenTelemetry tracing, and Gitar PR guardrails were wired up.
- Initial Kubernetes Checks in `team-takeaway` flagged default starter configuration items and ~1,800 `probe terminated redirects` warning events caused by `force_ssl` redirecting plain-HTTP kubelet probes on `/healthz` and `/readyz`.

## The story

- **What we built and who it helps at a conference:** We built [Takeaway](https://takeaway.cnh.radarhq.io) ([FinKrug/Takeaway](https://github.com/FinKrug/Takeaway)), a real-time Phoenix 1.8 + LiveView conference talk companion where attendees join with a 6-letter code to take autosaving notes and submit slide-tagged questions while speakers see a live Whisper/diarized transcript, question leaderboard, and keyboard/clicker slide controls ([PR #11](https://github.com/FinKrug/Takeaway/pull/11), [PR #18](https://github.com/FinKrug/Takeaway/pull/18), [PR #19](https://github.com/FinKrug/Takeaway/pull/19), [PR #20](https://github.com/FinKrug/Takeaway/pull/20), [PR #24](https://github.com/FinKrug/Takeaway/pull/24)).
- **How we shipped through Gitar, Radar, and Dash0:** Every change shipped via pull request reviewed by Gitar ([PR #2](https://github.com/FinKrug/Takeaway/pull/2), [PR #10](https://github.com/FinKrug/Takeaway/pull/10))—which caught and helped us fix four real issues before merge: skills still instructing direct pushes to `main` ([PR #10](https://github.com/FinKrug/Takeaway/pull/10#issuecomment-6750822310)), cookieless `GET /join/:code` requests creating unbounded attendee rows ([PR #18](https://github.com/FinKrug/Takeaway/pull/18#issuecomment-6752155078)), `Slide.changeset/2` casting the owning `speech_id` foreign key ([PR #20](https://github.com/FinKrug/Takeaway/pull/20#issuecomment-6752162612)), and `SpeakerLive` reading `slide_count` only at mount before async slide extraction finished ([PR #24](https://github.com/FinKrug/Takeaway/pull/24#issuecomment-6753260291))—before Argo CD synced `team-takeaway` in Radar and we verified error-free `service.version` spans (through `390e3c7`) in Dash0 ([PR #6](https://github.com/FinKrug/Takeaway/pull/6)).
- **What broke, what we checked, and what Radar showed:** When a missing comma in `mix.exs` broke the main build (`e2c8d2b`) and a subsequent `build-and-deploy` run failed on `f80fcb0` ([Run #42707921054](https://github.com/FinKrug/Takeaway/actions/runs/42707921054)), plus when we evaluated running Tesseract OCR inside the `app` pod (#302.1), Radar's workload resource view and cluster limits (`500m` CPU / `256Mi` RAM per pod under the 2 CPU / 4 GiB cluster budget) showed that in-pod OCR (100–200 MB RAM per page) would OOM-kill the web tier, leading us to extract PDF/PPTX text asynchronously in Elixir/`pdftotext` ([PR #20](https://github.com/FinKrug/Takeaway/pull/20)) and defer OCR to a separate worker Deployment.
- **The investigation and what we did with it:** Using Radar cluster events and diagnostics alongside Dash0 OpenTelemetry traces (`Takeaway.OtelSampler`), we investigated why Kubernetes logged ~1,800 `probe terminated redirects` warnings despite passing probes and exempted `/healthz` and `/readyz` from `force_ssl` in [`app/config/prod.exs`](https://github.com/FinKrug/Takeaway/blob/main/app/config/prod.exs) while filtering probe spans out of Dash0 so trace budgets stayed focused on real attendee and speaker requests.
- **Checks before and after:** Compared to our initial cluster state, `app` runs rootless (`runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `RuntimeDefault` seccomp, `drop: ["ALL"]` capabilities in [`deploy/deployment.yaml`](https://github.com/FinKrug/Takeaway/blob/main/deploy/deployment.yaml)), `/healthz` and `/readyz` bypass SSL redirects in [`app/config/prod.exs`](https://github.com/FinKrug/Takeaway/blob/main/app/config/prod.exs), and both `app` replicas run healthy and synced on `ghcr.io/finkrug/takeaway:390e3c7`.

## Screenshots to take in Radar Cloud

1. **Timeline (the day's changes):**
   https://app.radarhq.io/c/vyg02svjQsw/timeline
2. **Argo CD Application `app` (`Synced` + `Healthy`):**
   https://app.radarhq.io/c/vyg02svjQsw/resources/applications?resource=team-takeaway/app&apiGroup=argoproj.io
3. **Cluster Checks (`takeaway` scope):**
   https://app.radarhq.io/checks?scope=vyg02svjQsw
4. **Hosted AI Investigation:**
   https://app.radarhq.io/c/vyg02svjQsw
