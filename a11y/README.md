# Accessibility checks

## Automated (axe-core, runs in CI)

`axe.spec.mjs` runs axe-core (WCAG 2.0, 2.1 and 2.2, levels A and AA) through
Playwright against the main pages: `/`, `/join`, `/organizers/log_in`,
`/organizers/register`, and, after registering a throwaway organizer,
`/organizers` and `/speeches/new`. Any violation fails the test.

The `a11y` GitHub workflow (`.github/workflows/a11y.yaml`) boots the app against
Postgres on every pull request that touches `app/` or `a11y/` and runs it.

Run it locally with the app on port 4000:

    cd a11y
    npm install
    npx playwright install chromium
    BASE_URL=http://localhost:4000 npm test

Pages that need live state (attendee `/join/:code`, speaker view) are covered
by the manual audit below and by `app/test/takeaway_web/page_structure_test.exs`.
To add a page, append its path to `publicPages` in `axe.spec.mjs`.

## Manual VoiceOver audit

Record the results as a comment on parent card 463.

### iOS Safari (attendee)

Settings > Accessibility > VoiceOver on. Open `/join/<code>` for a live speech.

- [ ] Swipe through the page: every control has a meaningful spoken label
- [ ] Headings rotor lists one h1 and a sensible heading outline
- [ ] Question and tag controls announce their role and state (selected, pressed)
- [ ] Submitting a question announces the result (live region or flash)
- [ ] Live updates (new slide, speaker status) are announced without moving focus
- [ ] Focus is never trapped; modals/dialogs can be dismissed
- [ ] Works at largest Dynamic Type size and in landscape

### macOS Safari (speaker)

Cmd+F5 for VoiceOver. Log in as an organizer and open `/speeches/<id>/speak`.

- [ ] Skip link is first and moves to main content
- [ ] Landmarks rotor shows header nav and main
- [ ] Slide controls are reachable by keyboard and announce their purpose
- [ ] Transcript and question updates are announced politely, not interrupting
- [ ] Every control is operable with keyboard alone (VO + Space), visible focus
- [ ] Page titles are unique per page

### Results log

| Date | Platform | Tester | Findings |
| ---- | -------- | ------ | -------- |
|      |          |        |          |
