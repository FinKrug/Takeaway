# Seeds one demo event, speaker and speech. Safe to run repeatedly.
#
#     mix run priv/repo/seeds.exs
alias Takeaway.{Accounts, Repo, Speeches}
alias Takeaway.Accounts.User
alias Takeaway.Events.Event

event =
  Repo.get_by(Event, name: "Demo Conference") ||
    Repo.insert!(
      Event.changeset(%Event{}, %{
        name: "Demo Conference",
        description: "A demo event",
        tags: ["demo"],
        join_code: "DEMO01"
      })
    )

speaker =
  Repo.get_by(User, email: "speaker@example.com") ||
    with {:ok, user} <-
           Accounts.create_speaker(%{name: "Demo Speaker", email: "speaker@example.com"}),
         do: user

if Speeches.list_speeches(event.id) == [] do
  {:ok, speech} =
    Speeches.create_speech(%{
      title: "Hello, Takeaway",
      description: "A demo speech",
      tags: ["demo", "intro"],
      join_code: "SPEECH",
      event_id: event.id,
      speaker_id: speaker.id
    })

  {:ok, _} =
    Speeches.create_artifact(%{
      kind: "plan",
      title: "Speech plan",
      content: "1. Intro\n2. Demo\n3. Q&A",
      speech_id: speech.id
    })
end
