# Questions

The lifecycle of an audience question, from submission or transcript detection through filtering, context tagging, grouping, retraction and answering, plus the Elasticsearch layer that tagging and grouping rely on.

Related: [pipeline.md](pipeline.md) (transcript segments, slides, summaries), [domain-model.md](domain-model.md) (tables), [web.md](web.md) (LiveViews), [configuration.md](configuration.md), [deployment.md](deployment.md) (`deploy/elasticsearch.yaml`), [observability.md](observability.md).

## Overview

| Step | Code | Path |
|---|---|---|
| Submit typed question | `TakeawayWeb.SpeechLive.Join` -> `Takeaway.Questions.submit_question/4` | Request (attendee LiveView) |
| Filter | `Takeaway.Questions.filter_text/1` -> `Takeaway.Questions.Filter` | Request |
| Local context tag | `Takeaway.Questions.Tagging.attach_current/3` | Request |
| Broadcast `{:question_created, q}` | `Questions.broadcast/2` | Request |
| Index in Elasticsearch | `Takeaway.Elasticsearch.QuestionSync` | Background GenServer |
| Search-based enrichment | `Takeaway.Questions.TagWorker` -> `Tagging.enrich/1` | Background GenServer |
| Grouping | `Takeaway.Questions.GroupWorker` -> `Grouping.assign/1` | Background GenServer |
| Verbal questions | `Transcripts.record_segments/3` -> `Questions.create_verbal_questions/1` | Speaker LiveView (chunk processing) |
| Answered | `Questions.mark_answered_by_segments/2` | Speaker LiveView (chunk processing) |
| Retraction | `Questions.retract_question_by/2`, then `Grouping.retract/1`, `QuestionSync` | Request, then background |

All three background workers are started in `app/lib/takeaway/application.ex` and subscribe to the global topic `"questions:all"`.

## PubSub events

`Questions.broadcast/2` sends every event to both `"speech:<id>:questions"` (`Questions.topic/1`) and `"questions:all"` (`Questions.global_topic/0`), except where noted.

| Event | Sent by | Consumers |
|---|---|---|
| `{:question_created, q}` | `submit_question/4`, `create_verbal_questions/1` | Join, Show, SpeakerLive; QuestionSync, TagWorker, GroupWorker |
| `{:question_tagged, q}` | `Tagging.save/4` (both topics) | Join, Show, SpeakerLive; QuestionSync |
| `{:question_retracted, q}` | `retract_question_by/2` | Join, Show, SpeakerLive; QuestionSync, GroupWorker |
| `{:question_answered, q}` | `mark_answered_by_segments/2` | Join (Answered badge), Show; SpeakerLive ignores it |
| `{:question_groups_updated, speech_id}` | `Grouping.notify/1` (per-speech topic only) | Show (re-ranks groups) |

Workers subscribe on each app pod. With `DNSCluster` clustering the same event reaches every pod's workers, which is why tagging and grouping take row locks and are idempotent. `deploy/deployment.yaml` runs two replicas without `DNS_CLUSTER_QUERY`, so as deployed each event is only seen on the pod that produced it (see [pipeline.md](pipeline.md#who-receives-segments)).

## Submission

Source: `app/lib/takeaway_web/live/speech_live/join.ex`, `app/lib/takeaway/questions.ex`.

`Join.handle_event("submit_question", ...)` rejects, with an inline form error and nothing saved or broadcast, when:

| Check | Message |
|---|---|
| No session user (cookies blocked) | "turn on cookies to ask questions" |
| Speech not live (`started_at` set and `ended_at` nil) | "questions are open while the speech is live" |
| Less than 5 s since this LiveView's last accepted question (`@question_interval_ms`) | "wait a few seconds before asking again" |
| Form changeset: `text` required, max 500 chars (`@max_question_length`); `slide_number` > 0 | changeset errors |
| `Questions.filter_text/1` returns `{:error, reason}` | the filter's message |

The rate limit is per LiveView process (`last_question_at` assign), not per user.

The LiveView decides `slide_source` on the server (`slide_override?/2`): `"manual"` if the attendee edited or cleared the slide field, otherwise `"current"`. A submitted provenance parameter is never trusted.

`Questions.submit_question(speech, user, attrs, now)`:

1. Trims text, runs `filter_text/1`.
2. Inserts with `offset_ms = max(now - speech.started_at, 0)` (0 if not started), `source: "typed"`, `user_id`, `speech_id`, `slide_number`.
3. `Tagging.attach_current/3` (local data only, no Elasticsearch).
4. Broadcasts `{:question_created, question}` and returns it.

### Schema

`Takeaway.Questions.Question` (`app/lib/takeaway/questions/question.ex`):

| Field | Meaning |
|---|---|
| `text`, `speech_id` | required |
| `offset_ms` | submission time relative to speech start; never changed by tagging |
| `source` | `"typed"` (requires `user_id`) or `"verbal"` (no user) |
| `user_id` | asker of a typed question |
| `transcript_segment_id` | segment a verbal question came from; unique index |
| `slide_number`, `slide_source` | slide tag and how it was chosen: `current`, `manual`, `matched` |
| `context_segment_id`, `context_offset_ms`, `context_source` | transcript context and its start time; source `current` or `matched` |
| `tag` | display label, e.g. `Slide 4 · 12:34` |
| `group_id` | `question_groups.id` (plain integer field) |
| `retracted_at`, `answered_at` | lifecycle timestamps |

The changeset casts only `text, offset_ms, slide_number, group_id, user_id, speech_id, source, transcript_segment_id`; context and tag fields are written with `Ecto.Changeset.change/2` in `Tagging`.

## Filtering

`Questions.filter_text/1` uses `config :takeaway, :question_filter` if set (a 1-arity function or `{module, function}` returning `{:ok, text} | {:error, reason}`), else `Takeaway.Questions.Filter.filter/1`.

`Takeaway.Questions.Filter.check/1` (`app/lib/takeaway/questions/filter.ex`), in order:

| Check | Error |
|---|---|
| Not valid UTF-8 | "please enter a valid text question" |
| More than 8,000 bytes or 2,000 characters | "please keep your question to 2000 characters or fewer" |
| Blank | "type a question first" |
| Profanity | "please rephrase your question without profanity" |
| Not `Questions.question?/1` | "please ask a question about the talk" |
| No letter at all | "please ask a question about the talk" |

Error messages never echo the rejected text. The 500-char form limit in `Join` is stricter than the filter's 2,000.

### Question heuristic (`Questions.question?/1`)

True when the trimmed text ends with `?`, or, after skipping leading fillers (`so and but um uh ok okay well also then right`), the first word is a wh-word (`who what when where why how which whose whom` and their `'s` forms) or an auxiliary (`is are ... can could will ... haven't hasn't`) followed by a subject (`i you he she it we they this that these those there anyone anybody someone somebody everyone`). Curly apostrophes are normalized. This is also the transcript heuristic for verbal questions.

### Profanity

A fixed English word list (`@words`). Text is NFKC-normalized, lowercased, and common leetspeak substituted (`0 1 3 4 5 7 @ $` -> `o i e a s t a s`). It matches:

- whole words after splitting on non-letters;
- `@disguised`: a listed word with punctuation or symbols between letters (`f.u.c.k`);
- `@spaced`: a listed word with every letter separated by whitespace/punctuation (`f u c k`), anchored so a short word is not joined to a longer one.

Lookbehind/lookahead on letters and digits keeps clean substrings (`class`) from matching. It does not detect abusive meaning.

Verbal questions do not go through the filter.

## Context tags

Source: `app/lib/takeaway/questions/tagging.ex`. Tags are best-effort: failure never removes a saved question.

### At submission: `attach_current/3`

- Segment: for verbal questions, the source segment (`transcript_segment_id`); for typed ones, the "active" segment of the speech's transcript artifact where `start_ms <= offset_ms < end_ms` (latest start wins).
- Slide: if `slide_source` is `"manual"`, the attendee's number; else the speech's current slide re-read from the database (`SpeechCreator.current_slide/2` with a fresh `Slides.count_slides/1`). When `slide_source` is not passed, a present `slide_number` counts as manual.
- Exceptions are rescued and logged ("Question context unavailable"); the untagged question is returned.

Because `offset_ms` is measured from the speech's `started_at` while segment times are measured from when the speaker turned the mic on ([pipeline.md](pipeline.md#1-capture-in-the-browser)), the active-segment lookup assumes the mic was started at about the same time as the speech.

### `save/4` (shared by all tagging paths)

Runs in a transaction with `SELECT ... FOR UPDATE` on the question row:

- Retracted questions are left unchanged.
- A previous `context_source: "matched"` is never overwritten by a non-matched segment (late chunks or duplicate deliveries cannot erase a semantic match).
- Slide replacement: a manual slide is never replaced; an automatic slide can be set when none exists or refined by a `"matched"` slide.
- `tag` is `Tagging.label(slide, offset)`: `"Slide N · mm:ss"`, or `"mm:ss"` without a slide. The time is `context_offset_ms` if a context segment is set, otherwise the submission `offset_ms`.
- If the row changed and is not retracted, `{:question_tagged, updated}` is broadcast on both topics.

### In the background: `TagWorker`

`Takeaway.Questions.TagWorker` (`tag_worker.ex`) subscribes to `"questions:all"` and `"transcripts:all"` unless `config :takeaway, :question_tagging, false`. Errors are rescued and logged.

| Message | Action |
|---|---|
| `{:question_created, q}` | `Tagging.enrich(q.id)` |
| `{:transcript_recorded, speech_id, segment}` | `Tagging.attach_delayed(speech_id, segment)` |

`enrich/1` (skips retracted or missing questions):

- Typed questions: search the `transcript_segments` index (`match` on `text`) for a segment of the same speech. A hit is accepted only if the segment exists in Postgres, belongs to this speech's transcript, starts at or before the question's `offset_ms`, and has `Grouping.similarity/2 >= 0.15` with the question. Accepted -> `context_source: "matched"`; else the active segment with `"current"`.
- Typed questions whose slide is not manual: search the `slides` index (`multi_match` on `title`, `content`), accept a hit only if the slide row exists and similarity >= 0.15 -> `slide_source: "matched"`.
- Verbal questions: active segment only, no search.

Searches (`hits/3`) use `size: 5`, a `term` filter on `speech_id`, and `connect_options: [timeout: 200]`, `receive_timeout: 200`, `request_timeout: 250`, `retry: false`. Any error returns no hits.

`attach_delayed/2` handles segments that arrive after the question (STT lag): every non-retracted question of the speech with no `context_segment_id` and `segment.start_ms <= offset_ms < segment.end_ms` gets that segment, keeping its slide.

## Grouping

Source: `app/lib/takeaway/questions/grouping.ex`, `group_worker.ex`, `group.ex`.

`Takeaway.Questions.GroupWorker` subscribes to `"questions:all"` unless `config :takeaway, :question_grouping, false`. On `{:question_created, q}` it calls `Grouping.assign/1`; on `{:question_retracted, q}`, `Grouping.retract/1`. Exceptions are rescued and logged.

### Similarity

`Grouping.similarity/2` is Jaccard similarity of content-word sets: lowercase, split on non-letter/digit, minus a stop list (`a an the is are ... please explain tell me`). If either side has fewer than 2 content words the result is `0.0`, so generic one-word questions never group.

Threshold: `config :takeaway, :question_group_similarity` (default `@threshold 0.6`).

### `assign/1`

1. Outside the transaction: `Elasticsearch.more_like_this_question(speech_id, text)` (see [below](#queries)), timeouts 200/200/250 ms, no retry. Hits become candidate ids from `_id`. Errors and exceptions are logged and become `{:error, _}`.
2. Transaction: `SELECT ... FOR UPDATE` on the speech row (serializes assignment for the whole speech across replicas), then reload the question. If it is retracted or already has a `group_id`, nothing changes (idempotent for duplicate deliveries).
3. `best_match`:
   - ES failed: no match.
   - ES succeeded (even with zero hits): candidates = ES ids plus the 100 most recent non-retracted questions of the speech from Postgres (bridges ES refresh lag and simultaneous submissions). All are re-loaded from Postgres, filtered to the same speech, non-retracted, not the question itself, and scored; the highest score >= threshold wins.
4. Group: the match's group if it belongs to this speech; otherwise a new `question_groups` row with the question's text as representative. If the match itself has no group yet, it joins the same group.
5. After commit, broadcast `{:question_groups_updated, speech_id}`.

When Elasticsearch is down every new question gets its own single-member group.

`assign_pending/1` runs `assign/1` for every ungrouped, non-retracted question of a speech in id order. `Summaries` calls it before caching a speaker summary ([pipeline.md](pipeline.md#inputs)).

### `retract/1`

Same speech row lock. If the retracted question had a group: when other active members remain, the group's `text` becomes the earliest remaining member's text; otherwise all members' `group_id` is cleared and the group is deleted. Broadcasts `{:question_groups_updated, speech_id}`.

### Reading groups

`Questions.list_top_groups(speech_id, limit: 10)` groups non-retracted questions by `group_id` (ungrouped questions are singletons), takes the earliest member's text as label, sorts by count desc, text, id. `SpeechLive.Show` re-reads it on any question event. Counts are always derived from questions; `Group.count` is a virtual field.

## Retraction

`Questions.retract_question_by(id, user)` (`questions.ex`):

| Case | Result |
|---|---|
| Not found | `{:error, :not_found}` |
| Asked by someone else | `{:error, :forbidden}` |
| Already retracted | `{:ok, q}`, no broadcast |
| Otherwise | sets `retracted_at`, broadcasts `{:question_retracted, q}` |

Retracted rows stay in Postgres. `list_questions/2` excludes them unless `include_retracted: true`. Tagging ignores them. QuestionSync deletes the document from Elasticsearch, and Grouping repairs the group. Verbal questions have no user, so no one can retract them through this path.

## Verbal questions from the transcript

After each chunk's segments are saved, `Transcripts.record_segments/3` ([pipeline.md](pipeline.md#5-persisting-and-broadcasting-takeawaytranscripts)) does:

- If any new segment passes `question?/1`: `Questions.create_verbal_questions(speech_id)`. It scans all question-like segments of the speech (`Transcripts.list_question_segments/1`), skips those already linked to a question, and inserts `source: "verbal"`, `offset_ms = segment.start_ms`, `transcript_segment_id = segment.id`, no user. Each is tagged with `attach_current/3` and broadcast as `{:question_created, q}`. The unique index on `transcript_segment_id` (`priv/repo/migrations/20261109230200_add_source_to_questions.exs`) prevents duplicates even under a race; the insert error is dropped by the comprehension.
- If anything was saved: `Questions.mark_answered_by_segments(speech_id)`.

### Answering

`mark_answered_by_segments/2` sets `answered_at` on open verbal questions (not answered, not retracted, with a source segment) when some other segment:

- starts at or after the question segment's `end_ms`,
- is not itself a question (`question?/1`),
- and is not labelled with the same speaker as the question segment (unlabelled segments count as a response).

Each is broadcast as `{:question_answered, q}`. There is no manual "mark answered" action, and typed questions are never marked answered.

Both functions re-read the whole transcript of the speech on every chunk, so cost grows with talk length.

## Elasticsearch

Elasticsearch is a derived index. Postgres is the source of truth; every search result is re-checked against Postgres before use, and every ES failure degrades to local behaviour.

### Client: `Takeaway.Elasticsearch`

Source: `app/lib/takeaway/elasticsearch.ex`. Built on `Req`.

| Setting | Value |
|---|---|
| Base URL | `config :takeaway, :elasticsearch, url:` from `ELASTICSEARCH_URL` (default `http://localhost:9200`; cluster: `http://elasticsearch:9200`) |
| Auth | `Authorization: ApiKey <ELASTICSEARCH_API_KEY>` when set and non-empty |
| Default timeouts | connect 5,000 ms, receive 5,000 ms, request 5,000 ms |
| Retries | `retry: false` everywhere |
| Extra options | `config :takeaway, :elasticsearch, request_options:` is merged into every request |

Tagging and grouping searches override timeouts to 200/200/250 ms.

### Indices and mappings

Defined in `@indices`; created by `init_indices/0`.

| Index | Fields (type) | Doc id | Written by |
|---|---|---|---|
| `questions` | `speech_id` (keyword), `user_id` (keyword), `text` (text), `offset_ms` (integer), `slide_number` (integer), `tag` (keyword), `inserted_at` (date) | question id | `QuestionSync` |
| `transcript_segments` | `speech_id` (keyword), `segment_id` (keyword), `text` (text), `start_ms`, `end_ms`, `slide_number` (integer) | segment id | `Elasticsearch.Indexer.index_segment/1` |
| `slides` | `speech_id` (keyword), `slide_number` (integer), `title` (text), `content` (text) | `"<speech_id>_<slide_number>"` | `Elasticsearch.Indexer.index_slide/1` via `Slides.index_slides/1` |
| `notes` | `speech_id`, `user_id` (keyword), `body` (text), `offset_ms`, `slide_number` (integer), `inserted_at`, `updated_at` (date) | note id | nothing (see below) |

The question document also carries `id`, which is not in the mapping and is added by dynamic mapping. Verbal questions index `user_id` as `""`. Transcript documents have `slide_number: nil` (segments have no slide).

Because doc ids are deterministic, re-indexing overwrites rather than duplicates.

### Index setup: `ClusterSetup`

`Takeaway.Elasticsearch.ClusterSetup` (`elasticsearch/cluster_setup.ex`) runs `init_indices/0` asynchronously after boot (startup never blocks):

- Missing index (404): created with its mapping. `resource_already_exists_exception` is treated as success.
- Existing index: `GET /<index>/_mapping` and compare each declared field's `type`. Any difference returns `{:error, {:mapping_drift, index, fields}}`; setup logs an error and stops without retrying. It never modifies an existing index.
- Any other error (connection refused, timeout, unexpected status): retry every 5 s, up to `@max_retries` 29 (about 2.5 minutes), then log at debug and give up until the next app start.
- `config :takeaway, :elasticsearch, auto_setup: false` disables it (`config/test.exs`).

### Writers

`Takeaway.Indexer` (`app/lib/takeaway/indexer.ex`) is the behaviour for segment and slide indexing, chosen with `config :takeaway, :indexer` (`config/config.exs`: `Takeaway.Elasticsearch.Indexer`; `config/test.exs`: `Takeaway.Indexer.Noop`).

| Writer | Trigger | Sync/async | On failure |
|---|---|---|---|
| `Elasticsearch.Indexer.index_segment/1` | each saved transcript segment | `Task.start` (unsupervised, fire-and-forget); always returns `:ok` | warning logged, segment not indexed |
| `Elasticsearch.Indexer.index_slide/1` | `Slides.index_slides/1` in the extraction task | synchronous; returns `{:error, _}` | counted on the `slides.extract` span, warning logged |
| `Elasticsearch.QuestionSync` | `{:question_created, _}` and `{:question_tagged, _}`: re-reads the row from Postgres and indexes it, or deletes it if retracted. `{:question_retracted, _}`: deletes the document | synchronous in the GenServer | warning logged; 404 on delete counts as success |

`QuestionSync` is enabled unless `config :takeaway, :elasticsearch, auto_sync: false` (or `auto_sync:` in its start options).

There is no retry queue for any writer. A document that fails to index stays missing until the same entity is written again (a question re-indexes on its next `question_tagged`; segments and slides are never re-sent).

### Queries

| Function | Index | Query | Timeouts | Used by |
|---|---|---|---|---|
| `more_like_this_question/3` | `questions` | `more_like_this` on `text`, `minimum_should_match: "70%"`, `min_term_freq: 1`, `min_doc_freq: 1`, `size: 20`, `term` filter `speech_id` | 200/200/250 ms | `Grouping.assign/1` |
| `search/3` from `Tagging.hits/3` | `transcript_segments`, `slides` | `match` / `multi_match`, `size: 5`, `term` filter `speech_id` | 200/200/250 ms | `Tagging.enrich/1` |
| `search_questions/3`, `match_transcript_context/2`, `index_note/2`, `delete_note/2`, `search_notes/4`, `search_speech_notes/3` | various | | 5 s | not called from `app/lib` |

### When Elasticsearch is down

| Feature | Behaviour |
|---|---|
| Submitting, listing, retracting questions | Unaffected (Postgres only) |
| Live transcript | Unaffected; segment indexing tasks log warnings |
| Slide extraction | Slides stored in Postgres; `slides.index_failed` > 0 on the span |
| Context tags | Local tag from `attach_current/3` and `attach_delayed/2` only; no matched segment/slide. Each search costs at most ~250 ms in the TagWorker |
| Grouping | Each new question gets its own group (no DB-only fallback when the search errors) |
| Index setup at boot | Retries for ~2.5 min, then gives up until restart; with `action.auto_create_index=false` in the cluster, writes to missing indices then fail |

Documents missed during an outage are not backfilled automatically.

### Rebuilding an index

There is no rebuild task or release command in the repo. `Takeaway.Release` has no Elasticsearch functions, and `ClusterSetup` refuses to touch an index whose mapping has drifted.

To rebuild by hand from a release shell (`bin/takeaway remote`), using functions that exist:

1. Delete the index: `Takeaway.Elasticsearch.delete_index("questions")`.
2. Recreate all missing indices with current mappings: `Takeaway.Elasticsearch.init_indices()`.
3. Re-index from Postgres:
   - Questions: for each non-retracted `Takeaway.Questions.Question`, `Takeaway.Elasticsearch.index_question(q)`.
   - Transcript segments: for each speech, `Takeaway.Transcripts.list_segments(speech_id)` and `Takeaway.Elasticsearch.Indexer.index_segment(%{seg | artifact: artifact})` (or call `Takeaway.Elasticsearch.index_transcript_segment/2` with a map containing `segment_id`, `speech_id`, `text`, `start_ms`, `end_ms`).
   - Slides: `Takeaway.Slides.list_slides(speech_id) |> Takeaway.Slides.index_slides()`.

Restarting the app after step 1 also recreates the index (step 2) via `ClusterSetup`.

Between steps 1 and 2 writes to that index fail: the cluster sets `action.auto_create_index=false` (`deploy/elasticsearch.yaml`), so only `init_indices/0` can create indices, with the explicit mappings. The same applies if `ClusterSetup` gave up before Elasticsearch came up: writes fail until the app restarts or `init_indices()` is run.

In the cluster, Elasticsearch is a single node (`deploy/elasticsearch.yaml`: `elasticsearch:8.17.0`, `discovery.type=single-node`, `xpack.security.enabled=false`, 256 MB heap, 2Gi volume). See [deployment.md](deployment.md).
