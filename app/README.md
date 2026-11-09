# Takeaway

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

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

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
