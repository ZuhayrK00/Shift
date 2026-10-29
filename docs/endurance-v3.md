# Endurance planning and profile — 2.1.0 (21)

## Calendar and navigation

The combined calendar, month dots, widget agenda and Watch agenda now use only explicitly saved appointments and completed activities. The previous calendar projection synthesized dated gym sessions from legacy weekly workout preferences, which could appear as unexpected Monday/Wednesday/Friday appointments. That projection is removed without deleting actual sessions or changing the separate weekly workout preferences.

Endurance now starts with its heading and recording controls. Progress, saved routes and plans are grouped in Your training below the weekly summary. Build my week opens the new endurance coach and planner; it is also available from Training plans.

Both iPhone and Watch register the `shift` URL scheme used by Endurance widget and complication links. The existing `com.zuhayrk.shift` iPhone scheme remains registered for existing shortcuts and authentication callbacks.

## Profile

Profile has a combined weekly overview, grouped goals, a body-progress journal and a shared records section. Strength and Endurance retain violet/teal accents. Weekly consistency includes the existing combined frequency calculation; the overview separately labels gym count, endurance distance and endurance active time. Existing weight/step/frequency editors, exercise goal details, locked-photo behaviour, body progress, personal bests and settings remain accessible.

The presentation is a standalone SwiftUI layout driven by real repository data. Saved preview images use fictional data and the actual layout source, rendered natively in light/dark and with two Dynamic Type configurations. They are layout checks, not screenshots from an iPhone or proof of iOS accessibility behaviour.

## Coach and planner

The coach uses the same Apple Foundation Models approach as the existing gym AI features. It is gated by runtime Apple Intelligence availability on iOS 26+. Unsupported or unready devices retain the full manual planner. There is no cloud AI provider or new API key. Chat stays in memory for the screen and clears on account changes; only a bounded recent transcript is passed to the on-device model. Responses cannot change the calendar. The model is instructed to avoid invented history, weather and claims of saving, and to direct scheduling to the review flow.

Guided generation can interpret run/walk/cycle, weekly frequency, duration and explicitly supplied day/time windows. Model output is validated, bounded and editable. Ambiguous availability should be completed manually. Goals are 1–7 sessions of 5–180 minutes, over seven calendar days, with at most one suggested session per day. Users add day-specific availability windows; none are preselected. Multiple windows per day are supported, including an end at midnight.

The scheduling engine is deterministic. It evaluates candidate times every 30 minutes within availability, excludes overlapping saved appointments and past times, and ranks days by forecast rain, wind, temperature, UV and daylight preferences. Full-session hourly coverage is required before calling a suggestion forecast-backed. Partial coverage still excludes known hazardous or dark hours. Missing/stale forecasts stay explicitly unverified. It never invents extra available days to fill an infeasible target. Forecast thresholds are planning heuristics, not a guarantee of outdoor safety.

The user reviews and can remove suggestions before a single atomic calendar save. Saving rechecks the account, the current calendar and whether times have passed. Existing reminders, sync, widget snapshots and Watch agenda refresh through the normal scheduling service. Sessions keep their forecast provenance and cautions as notes. Saved times do not automatically move as the forecast changes; calendar editing remains available.

## Apple Weather

WeatherKit capability **and** WeatherKit under App Services were enabled and re-opened to verify persistence for App ID `com.zuhayrk.shift` (identifier `4YSZD94552`, team `7NW33277C8`) on 25 October 2026 (London). The app entitlement is `com.apple.developer.weatherkit`; the Weather service is called only on iPhone. The release archive and exported package must retain this entitlement.

Weather is an account-scoped local opt-in. A one-shot location request uses kilometre desired accuracy; it does not start route recording. Users can instead enter a city. A manually chosen city is kept in memory for that app session. Location permission denial, location timeouts and forecast errors have explicit states and retain manual planning. Account changes clear in-memory weather, pending lookups and alerts. Account deletion also clears the weather preference.

The app caches a successful forecast for 15 minutes and treats it as unverified after an hour. Current conditions appear beneath the start button; provider weather alerts retain their source names, unmodified summaries and original detail links. The planner uses hourly data only within its available horizon. WeatherKit attribution and data-source links are displayed. Native measurements use the system temperature format; compact Watch/widget summaries explicitly label Celsius.

A recent city-level summary is shared with the existing private Watch/widget snapshot. It includes no coordinates. The medium Endurance widget and Watch Endurance screen can show it; stale summaries expire independently of weekly totals. A future widget timeline entry removes weather at expiry even before a later refresh. The Watch summary identifies that it came from iPhone. Widgets and Watch do not request WeatherKit directly. Existing Pro gating remains unchanged.

## Full-history Apple Health import

All history is now the default, with no lower date bound or result limit. Last year and Last 90 days remain optional filters. Completed walking, hiking, running and cycling workouts are queried, including indoor workouts. Hikes use the walking sport with an explicit Hike title. Daily step counts and walking-distance aggregates without a recorded workout are not fabricated into sessions.

Queries use cancellable native HealthKit async descriptors. Stable owner-scoped Health UUID identities and existing imports prevent duplicates. Shift-origin workouts remain excluded to avoid duplicating native Shift/Watch records. A failed or unavailable map does not prevent importing the workout details; missing maps can be retried later. Route upgrades preserve existing activity edits.

Import no longer reloads all prior activities, reminders and widgets for each saved row. Each record is durably saved with its cloud mutation, and a single end-of-import refresh/flush handles completion, cancellation or failure. Completed rows are kept and another import continues through deduplication. Historical imports do not infer calendar completion or trigger achievement alerts. The report shows walks/hikes, runs and rides found, new/existing records, unavailable maps and route errors. Read access denial can be indistinguishable from no returned Health data, and the UI explains how to check access.

## Verification

The full generic iOS simulator build passed for iPhone, Watch and widgets after the feature changes. Final release-only edits are also validated by the release archive. Seventy-four native XCTest cases passed with the actual shared models, SQLite persistence, calendar projection, import/report models, notification policies and SwiftUI layout/card source. These include the existing 59 tests with the old implicit-calendar test updated, 14 new planning/import tests, and one native Profile rendering case producing four previews. New tests cover availability, conflicts, forecast gaps and stale data, hazardous conditions across an entire session and partial forecasts, daylight, insufficient available days, duplicate windows, DST gaps, forecast provenance, all-history ranges and weather-summary expiry.

Native macOS tests do not replace iPhone/Watch runtime checks. The earlier iOS simulator runtime test launch was blocked by an unresponsive test-manager process; it is not reported as passing. Live Apple Weather responses, on-device AI generation, real Health library counts/permissions, widget refresh and Watch behaviour require physical-device checks. No customer Health library was read to claim these behaviours were field-tested.

Public Apple references: [WeatherKit and attribution](https://developer.apple.com/weatherkit/), [hourly weather](https://developer.apple.com/documentation/weatherkit/hourweather), [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [HealthKit async queries](https://developer.apple.com/documentation/healthkit/hksamplequerydescriptor).

Release processing and TestFlight confirmation are recorded below when complete.

## Release archive verification

The Release archive succeeded on 25 October 2026 (London). All four archived bundles report 2.1.0 (21). Deep/strict signature verification passed. The signed iPhone entitlements and embedded provisioning profile both contain WeatherKit=true. Both iPhone and Watch register `shift`; the existing iPhone authentication/shortcut scheme is retained. The archive log is saved under `build/testflight-2.1.0-21/`.

App Store Connect upload succeeded at 01:22 BST on 25 October 2026. Processing and internal-group availability are checked separately below.

Apple's Build Uploads entry for 2.1.0 (21), UUID `6bef154b-6812-490f-b34c-bcca3c6dcdeb`, reports Complete. Internal testing-group and saved-note verification follow below.

## TestFlight confirmation

Build 21 finished Apple processing (Build Uploads: Complete). Its Test Information page identifies 2.1.0 (21), with Team (Expo) attached as Internal and one tester. What to Test notes were saved and verified with Apple's Saved confirmation. The final screenshot is `build/testflight-2.1.0-21/ready.jpg`. This is an internal TestFlight release; no public App Store submission was made.
