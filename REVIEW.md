# Open button hit area

`AlexiaHubPersonal/` is extracted unchanged from the published 1.1.2 ZIP in the
first commit. The next commit changes only the shared app launcher button label
and adds this review note. The published ZIP and update feed are unchanged.

The launcher now places its padding, background, and rectangular `contentShape`
inside the `Button` label, using the plain button style. The same action handles
clicks on the text and the surrounding padding for all four launchers. Native
Button semantics and keyboard activation are preserved.

## Manual macOS verification

1. Build with `cd AlexiaHubPersonal && swift build -c debug`.
2. Launch the app and select Apps.
3. For each Open button, click its text, left/right padding, and top/bottom
   padding. Each click should invoke its launcher once. Browser/app launches and
   app-selection dialogs are expected effects; cancel selection when needed.
4. Click just outside the button. It should not invoke the launcher.
5. With keyboard navigation enabled, focus an Open button and press Space.
   Confirm its action runs once.

The original report has no matching issue or PR in this repository. The source
shows a native bordered button, but the intermittent runtime failure has not
been reproduced; the explicit label hit area addresses the reported symptom.

The latest Pages workflow passed. The previous run's build and status-report
jobs passed, while deployment was cancelled. Its deployment logs return 404,
so the exact cancellation cause is unconfirmed. These are deployment checks,
not Swift compilation or UI tests.
