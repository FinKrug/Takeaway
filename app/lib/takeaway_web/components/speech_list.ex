defmodule TakeawayWeb.SpeechList do
  @moduledoc """
  The "my speeches" lists on the organizer, speaker and attendee home pages: speeches
  grouped by conference (event), each with its status (live, upcoming, ended) and join
  code, plus a one-line count of each status.
  """
  use TakeawayWeb, :html

  alias Takeaway.Speeches.Speech

  @status_rank %{live: 0, upcoming: 1, ended: 2}

  @doc """
  Groups speeches by conference: `[{event | nil, speeches}]`. Speeches inside a group are
  live first, then upcoming, then ended (newest first within each). Groups with a live or
  upcoming talk come first; standalone talks (no conference) come last.
  `extra_events` adds conferences that have no speeches yet (an organizer's empty events).
  """
  def group_by_conference(speeches, extra_events \\ []) do
    groups =
      speeches
      |> Enum.group_by(& &1.event_id)
      |> Enum.map(fn {_event_id, [first | _] = list} ->
        {first.event, Enum.sort_by(list, &{@status_rank[Speech.status(&1)], -&1.id})}
      end)

    present = MapSet.new(groups, fn {event, _} -> event && event.id end)

    empty =
      for event <- extra_events, not MapSet.member?(present, event.id), do: {event, []}

    Enum.sort_by(groups ++ empty, fn {event, list} ->
      best = list |> Enum.map(&@status_rank[Speech.status(&1)]) |> Enum.min(fn -> 3 end)
      {is_nil(event), best, -(event && event.id || 0)}
    end)
  end

  @doc "`%{live: n, upcoming: n, ended: n}` for a list of speeches."
  def status_counts(speeches) do
    Enum.reduce(speeches, %{live: 0, upcoming: 0, ended: 0}, fn s, acc ->
      Map.update!(acc, Speech.status(s), &(&1 + 1))
    end)
  end

  @doc "\"Signed in as <role>\" above a home page's heading."
  attr :icon, :string, required: true
  attr :role, :string, required: true

  def role_eyebrow(assigns) do
    ~H"""
    <p id="role" class="flex items-center gap-2 text-sm text-muted">
      You're signed in as
      <.badge tone="brand" class="role-badge">
        <.icon name={@icon} class="size-3.5" /> {@role}
      </.badge>
    </p>
    """
  end

  @doc "Live, upcoming or ended, as a badge."
  attr :speech, :map, required: true

  def status_badge(assigns) do
    assigns = assign(assigns, :status, Speech.status(assigns.speech))

    ~H"""
    <.badge :if={@status == :live} tone="success" class="status-live">
      <span class="size-1.5 rounded-full bg-current motion-safe:animate-pulse" aria-hidden="true" />
      Live now
    </.badge>
    <.badge :if={@status == :upcoming} tone="brand" class="status-upcoming">Upcoming</.badge>
    <.badge :if={@status == :ended} tone="neutral" class="status-ended">Ended</.badge>
    """
  end

  @doc """
  A row of counts, e.g. "1 live · 2 upcoming · 3 ended", with role-specific words.
  """
  attr :counts, :map, required: true
  attr :labels, :map, default: %{live: "live now", upcoming: "upcoming", ended: "ended"}

  def status_summary(assigns) do
    ~H"""
    <dl id="status-summary" class="grid grid-cols-3 gap-2 sm:gap-3">
      <div
        :for={key <- [:live, :upcoming, :ended]}
        id={"count-#{key}"}
        class={[
          "rounded-xl px-3 py-2.5",
          key == :live && @counts.live > 0 && "bg-success-soft text-success",
          not (key == :live && @counts.live > 0) && "bg-sunken"
        ]}
      >
        <dt class="text-xs font-semibold uppercase tracking-wide opacity-80">{@labels[key]}</dt>
        <dd class="font-display text-2xl font-semibold tabular-nums">{@counts[key]}</dd>
      </div>
    </dl>
    """
  end

  @doc """
  Speeches grouped by conference. The `:meta` slot adds a line under each title; the
  `:actions` slot renders each speech's buttons. Both receive the speech. The `:group_actions`
  slot renders buttons next to each conference heading and receives the event (never nil).
  """
  attr :groups, :list, required: true
  attr :empty_group, :string, default: "No speeches yet."
  slot :meta
  slot :actions
  slot :group_actions

  def conference_groups(assigns) do
    ~H"""
    <div id="conferences" class="space-y-8">
      <section
        :for={{event, speeches} <- @groups}
        id={if event, do: "conference-#{event.id}", else: "standalone"}
        class="conference space-y-3"
        aria-labelledby={if event, do: "conference-#{event.id}-name", else: "standalone-name"}
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h2
            id={if event, do: "conference-#{event.id}-name", else: "standalone-name"}
            class="flex min-w-0 items-center gap-2 font-display text-lg font-semibold"
          >
            <.icon
              name={if event, do: "hero-calendar-days", else: "hero-presentation-chart-bar"}
              class="size-5 shrink-0 text-brand"
            />
            <span class="min-w-0 truncate">
              {if event, do: event.name, else: "Standalone talks"}
            </span>
            <span class="text-sm font-normal text-muted">
              · {length(speeches)} {if length(speeches) == 1, do: "talk", else: "talks"}
            </span>
          </h2>
          <div :if={event && @group_actions != []} class="flex shrink-0 gap-2">
            {render_slot(@group_actions, event)}
          </div>
        </div>

        <p :if={speeches == []} class="text-sm text-muted">{@empty_group}</p>

        <ul class="space-y-3">
          <li :for={speech <- speeches} id={"speech-#{speech.id}"}>
            <.card
              tone={if Speech.status(speech) == :live, do: "brand", else: "default"}
              class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
            >
              <div class="min-w-0 space-y-1">
                <div class="flex flex-wrap items-center gap-2">
                  <span class="min-w-0 truncate font-semibold">{speech.title}</span>
                  <.status_badge speech={speech} />
                </div>
                <p class="flex flex-wrap gap-x-3 gap-y-1 text-sm text-muted">
                  <span>
                    Join code
                    <span class="join-code font-mono font-semibold tracking-wider text-ink">
                      {speech.join_code}
                    </span>
                  </span>
                  {render_slot(@meta, speech)}
                </p>
              </div>
              <div :if={@actions != []} class="flex shrink-0 flex-wrap gap-2">
                {render_slot(@actions, speech)}
              </div>
            </.card>
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
