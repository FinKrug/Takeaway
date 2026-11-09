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

## Organizer accounts

Organizers register at `/organizers/register` and log in at `/organizers/log_in`
(PBKDF2-SHA256 password hashes; the session cookie holds only the organizer id).
An organizer owns events (`events.organizer_id`); creating a speech at `/speeches/new`
puts it in the organizer's event, created on first use.

Only the owning organizer can open the organizer pages. Everyone else is redirected
to the login page, or to `/` when the event or speech belongs to someone else:

* `/organizers`: dashboard listing the organizer's events with a **Manage tickets** link
* `/events/:id/tickets`: generate and import tickets
* `/speeches/:code`: speech control page (also links to the tickets and speaker pages)
* `/speeches/:id/speak`: speaker page with the live transcript

`/join/:code` (attendees) stays public. The per-event `admin_token` links no longer
work; the column is left in place and unused.

Events created before organizer accounts have no owner and are closed to everyone until
claimed. After registering, run in the release:

    bin/takeaway rpc 'Takeaway.Release.claim_unowned_events("me@example.com")'
