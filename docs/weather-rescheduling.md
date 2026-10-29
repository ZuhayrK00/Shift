# Forecast change suggestions

Source work for the next update. This feature is not part of the already-approved 2.1.0 (24) binary, and no new App Store or TestFlight build has been uploaded for it.

## Behaviour

Shift Pro users can opt in to forecast watching while creating a generated week. A future scheduled run, walk or ride can also opt in through Weather preferences, with explicit availability and a duration of 5–180 minutes. Existing sessions do not have availability inferred from old notes.

The saved session carries an optional Codable context: availability windows, original seven-day horizon, planning time zone, weather preferences, baseline covering the full session, Calendar-check choice and a rounded weather lookup point. Existing JSON records decode without it. Existing envelope storage, private sync, export and deletion carry the context without a new database migration. It is removed from Watch/widget summary payloads.

The deterministic review policy checks fresh hourly coverage for the whole planned session. It detects new rain, wind, temperature, daylight, UV and hazardous-condition concerns; small rain fluctuations do not trigger a suggestion. Candidates must fit availability, remain in the saved week, have complete fresh forecasts, avoid Shift/Calendar conflicts and offer a meaningful improvement. The one-session-per-day structure of generated plans is preserved. If there is no suitable alternative, the review explains this and retains the original time.

Nothing moves automatically. Move to this time opens confirmation with both dates. Confirmation verifies Pro again, reloads the session and completion/recording state, requests a fresh forecast, rechecks Calendar and only accepts the exact replacement the user saw. SQLite compare-and-replace checks the original row and local conflicts in the same transaction as the update and outbound sync mutation. Deleted, edited, skipped, completed, started and near-start sessions cannot be moved using an old suggestion. Keep original time records the dismissed change; a different worsening can be reviewed later.

Changing time, sport or duration in the normal editor resets watching so the old baseline is not reused. Weather preferences can rearm it from a new forecast. Session identity, duration, routes and program links survive a confirmed move, and normal reminder/summary reconciliation updates Watch and widgets. Apple Calendar events are never edited.

## Checks and notifications

Foreground checks are cached for 15 minutes; users can explicitly refresh. Background checks use a registered SwiftUI app-refresh task, the fetch background mode and a matching permitted identifier. Requests ask to run no earlier than three hours later. iOS decides actual timing and may not run them. Background execution respects task cancellation and does not request live location or Calendar permission.

Forecast notifications are opt-in, require Pro and notification permission, and use the existing durable event ledger. At most one is delivered per account/device per 24 hours; a repeated event is not redelivered. Tapping opens the relevant training calendar, where Forecast changes is available. No notification action moves a session. Sign-out clears in-memory reviews and account-owned notifications; account deletion also clears local alert cooldown state. Permissions and live forecast failures fail closed.

## Validation

- 39 native XCTest cases passed: 17 new review-policy cases, eight transactional store cases and 14 existing planning regressions. Tests compile the actual shared source, database migrations and repository. The native harness excludes iPhone orchestration; it does not replace a simulator UI test.
- Generic iOS Simulator build passed for phone, Watch, widgets and complications, with capture helpers excluded.
- The actual new SwiftUI review screen was built and launched on an iOS 26.5 simulator with fictional local capture data. The complete suggestion card, original/replacement times and both actions were visually checked. No live Apple forecast or personal Calendar/Health data was used for this preview.
- Git whitespace checks and background-task identifier/purpose-string checks passed.

Native model/repository tests do not establish actual background wake frequency, WeatherKit responses, permission prompts, OS alert delivery or Watch/widget refresh on hardware. A disconnected Watch recording may not be known to iPhone until transfer; session identity is preserved across any confirmed move. Validate live forecast refresh, Calendar access changes, foreground/background notifications, confirm/keep actions and paired-device updates on physical devices before distributing this update.

Apple references: [background refresh timing](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate), [background task configuration](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app).
