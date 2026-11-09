# Phoenix app gotchas (app/)

Full conventions are in `app/AGENTS.md`. These are the ones that cause real bugs or outages here.

## Migrations run while old pods still serve

The `migrate` init container runs `bin/migrate` before the new pods start, while the previous version keeps serving traffic. A migration must be safe for the *old* code too:

- Flag dropping or renaming a column or table that the current code still reads. Do it in two releases: stop using it, then drop it.
- Flag adding a `NOT NULL` column without a default to a table that has rows.
- Flag long-running data backfills inside a migration. The pod won't become ready until it finishes.
- Migrations must be generated with `mix ecto.gen.migration` (timestamped names), not hand-named.

## Runtime config

- New required env vars belong in `config/runtime.exs` (not `config/prod.exs`, which is baked into the image at build time) and must `raise` with a clear message or have a safe default.
- Every env var read in `runtime.exs` for prod must be set in `deploy/deployment.yaml`. A missing one crashes the release at boot.

## Health endpoints

- `/healthz` and `/readyz` must stay outside the `:browser` pipeline (no session, no CSRF), and must not be put behind auth.
- Liveness (`/healthz`) must stay cheap and must not depend on the database. Otherwise a DB blip restarts every pod.

## Security

- `String.to_atom/1` on user input.
- Programmatically set fields (owner ids, roles, status) listed in `Ecto.Changeset.cast/3`. They must be set explicitly.
- Raw SQL built by string interpolation instead of Ecto queries or parameters.
- LiveDashboard or other `dev_routes` exposed outside the `:dev_routes` guard.
- Inline `<script>` tags in HEEx templates. Use colocated hooks or `assets/js`.

## Correctness

- Ecto associations used in templates must be preloaded (N+1 or `Ecto.Association.NotLoaded` errors).
- Collections in LiveViews should use streams, not plain list assigns.
- New controllers and LiveViews need tests under `app/test/`. Tests should use element IDs (`has_element?/2`), not raw HTML matching.
- Code should pass `mix precommit` (format, compile warnings as errors, tests).
