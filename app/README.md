# Takeaway (Phoenix app)

See the [root README](../README.md) for what the app does, configuration and deployment.

```bash
mix setup        # deps, database, assets
mix phx.server   # http://localhost:4000 (or iex -S mix phx.server)
mix test
```

## Post-speech summaries

The speaker's **End Speech** button sets `ended_at` and broadcasts `{:speech_ended, speech}`.
`Takeaway.Summaries` then generates, once, and caches in the `summaries` table:

* a speaker summary (shown on `/speeches/:code`): prose summary, top question groups
  (by `group_id`) and the time buckets where questions spiked;
* an attendee summary per user (shown on `/join/:code` when the session has a `user_id`):
  cliffnotes merged with that attendee's own notes, generated on first view.

Prose comes from `Takeaway.LLM`. Set `ANTHROPIC_API_KEY` (optionally `ANTHROPIC_MODEL`) to use
Claude; without it, or if the call fails, an extractive fallback is stored. Speeches with no
transcript and/or no questions yield a summary that says so.
