# Endurance expansion — build 20

## iPhone

- The calendar button beside the mode pill opens a shared month grid. Violet marks planned gym sessions, teal marks endurance, and green marks completed training. Existing weekly gym schedules appear without being duplicated. A session from that schedule can be edited to set a specific time.
- Plan, move, skip, restore or delete a gym workout, run, walk or ride. Add optional distance/time targets, notes, a gym plan or a saved route. Starting an explicit gym appointment uses a stable session ID. Starting elsewhere links automatically only when one unfinished matching appointment exists that day.
- Endurance activity details include the map, measured kilometre splits, pace/speed and GPS elevation charts, personal-best badges and notes. Finishing an iPhone recording opens the summary.
- Progress shows six monthly distance totals, activity counts, active time, sport filtering, measured kilometre-block time records, longest activities and milestones. Timed records require complete, consecutive measured splits; they are never extrapolated from imported totals.
- Flexible walking, running and cycling templates populate the calendar as one atomic local transaction and one program group. Individual sessions remain editable. Removing a program's remaining sessions preserves completed activities.
- Save a completed activity's route with a private name, repeat it, and review linked efforts. The saved map is a reference, not directions, road snapping, route planning or turn-by-turn navigation.
- Share cards render locally as images. They exclude route shape by default; including it requires turning on the share-sheet option. Cards contain no email or account identifier.

## Watch and widgets

The Watch app has a new Endurance screen: run/walk/cycle, precise GPS preparation, native HealthKit workout sessions, pause/resume, distance, active time, pace/speed, available heart rate/calories, finish/save and discard. It shows upcoming gym/endurance appointments, endurance goals and saved-route quick starts. Gym appointments with plans and freestyle gym appointments can be started from the Watch calendar. The iPhone remains the place to edit plans, browse full progress and view saved maps.

The Watch uses HealthKit's workout session for background execution. Accepted location samples feed the same distance/split/outlier logic as iPhone and the Health workout route builder. Native Health workouts carry `ShiftEnduranceId` metadata so importing from Apple Health does not create another Shift activity. HealthKit route-writing failure does not delete the completed Shift recording.

Recovery checkpoints are account scoped. A recovered activity is paused at its last checkpoint. If HealthKit can recover its active workout session, resume is available; otherwise save the recovered activity and begin a new one. Background GPS and battery behaviour require physical-device verification.

Completed activities are written atomically to a private Watch outbox before transfer. File transfer avoids the small message-size limit for GPS routes. iPhone validates schema, owner, activity and size, saves durably to SQLite with its cloud mutation, and acknowledges the activity ID and file revision. Watch deletes only that acknowledged revision; changed files and failed/wrong-account transfers remain available for retry. Duplicate deliveries upsert the same activity ID. A durable local receipt prevents an acknowledged activity deleted on iPhone from being resurrected by a late Watch retry. Later Health identity updates preserve the saved activity. Account changes suspend the previous recording without exposing it in the new account. Account deletion queues an owner-scoped cleanup for paired Watch checkpoints and outbox files; ordinary sign-out retains private recovery data. Apple Health originals are managed separately in Health.

Two new iPhone widgets show endurance distance/activity time/quick starts and the combined upcoming training agenda. A new Watch complication shows endurance distance and opens Endurance. All retain Shift's existing Pro entitlement rules and privacy-sensitive rendering. Snapshot data is owner bound, and old weekly endurance totals reset independently of fresh step-count updates. Widgets and Watch use violet/teal accents matching iPhone. Watch summaries identify that their totals were synced from iPhone; unsynced recordings show a separate saved/pending state.

## Notifications

Settings → Notifications adds two opt-ins, disabled by default for existing and new accounts:

- Planned session reminders, with 15, 30 or 60 minute lead time.
- Endurance achievements for new Shift recordings: personal bests, milestones and crossed endurance goals.

Reminders cover dated calendar appointments, including gym workouts. They are rebuilt on account preparation, foreground, settings changes, scheduling/editing/skipping/deletion, sync and activity changes. Started and completed sessions are excluded. Up to 24 nearest future reminders are scheduled, leaving room for the existing notification features; the rolling queue refreshes when the app next runs. Weekly gym schedule entries without a chosen time must be edited to set one before they can have a timed reminder. Delivered alerts follow the user's iOS/Watch notification settings.

Historical imports and stale recordings do not create achievement alerts. Repeated activity IDs and already-crossed goals do not announce again during normal retries/sync. Achievement delivery uses the existing durable notification event ledger. Notification deep links persist through cold launch, validate the owning account and open the calendar date or Endurance. Sign-out cancels account-owned reminders and achievements.

## Storage and deployment

Migration `028_endurance_training.sql` creates only `training_sessions` and `endurance_routes`, with owner policies, anonymous access revoked, validation and Auth-user deletion cascades. It was applied to Shift project `dtzlfvuazdrgyyutjysm` through the SQL Editor on 24 October 2026 (London). Production verification confirmed row security enabled, one owner policy per table, anonymous SELECT denied and authenticated SELECT granted.

The new records use the existing SQLite envelope, FIFO mutation queue and complete-snapshot reconciliation. Program creation is atomic locally. Account deletion and JSON export include calendar sessions and saved routes. The Watch privacy manifest now includes linked fitness, health, precise location and account ID for app functionality; no tracking is enabled.

## Verification

The full iPhone/Watch/widget simulator build passed. Both the existing endurance and new training-schema PostgreSQL integration scripts passed in disposable PGlite databases, covering RLS isolation, anonymous denial, validation and deletion cascades. All 59 focused XCTest cases passed in a native macOS validation package using the actual shared models, SQLite database/store, calendar projection, notification policy and SwiftUI share-card source. The test package linked the existing GRDB checkout; only the image-output bridge was adapted from UIKit PNG to AppKit PNG. This covers 23 existing endurance tests, 17 new training tests and 19 notification tests. A separate direct native run passed 42 tracking/planning/reminder/transfer checks. Rendered card PNGs and the native test log are saved in `build/testflight-2.1.0-20/`.

The iOS 27 simulator build passed for iPhone, Watch and widgets. Focused runtime test attempts on iOS 27 and iOS 26.5 stalled before starting any tests: the simulator's test-manager launch was unresponsive. They are not reported as passing. Native validation does not replace iPhone/Watch field testing. Release archive/upload results are recorded below when complete.

Physical checks before public release: outdoor run/walk/ride; Watch wrist-down recording and phone-disconnected save/reconnect; pause/resume and termination recovery; partial Health/location permission; old/new paired app versions; a transfer retried around an account switch; notifications allowed/denied, rescheduled and cancelled; actual iOS/Watch alert delivery; calendar and share cards in both themes; and widget refresh at day/week rollover. Simulator tests do not establish those device behaviours.

Apple API references: [workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions), [workout route builder](https://developer.apple.com/documentation/healthkit/hkworkoutroutebuilder).

## Release archive

On 25 October 2026 (London), the Release archive succeeded for version 2.1.0 build 20. The archived iPhone app, iPhone widget extension, Watch app and Watch complication all report 2.1.0 (20). Deep, strict code-signature verification passed. The Watch archive includes the workout-processing background mode.

The App Store Connect upload completed successfully at 00:36 London time. Apple processing and internal-group availability are verified separately below.

App Store Connect lists build UUID `ab0788b5-9505-4363-ae91-f49cf95f064c` as version 2.1.0 (20), attached to the existing Team (Expo) internal group with one tester. The What to Test notes were saved and verified with Apple's Saved confirmation. Screenshots are in `build/testflight-2.1.0-20/`.

Final verification: Apple's Build Uploads row for 2.1.0 (20) reports **Complete**. Its build row reports Ready to Submit (external testing state), Team (Expo), and one invited internal tester. Internal distribution is attached; no public App Store submission was made. Saved proof: `build/testflight-2.1.0-20/ready.jpg` and `notes-saved.jpg`.
