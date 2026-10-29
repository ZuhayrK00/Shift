# Endurance polish — 2.1.0 (23)

25 October 2026, Europe/London.

## Changes

- Replaced the endurance goal Form with a target-first editor: editable large value, increment/decrement controls, presets, sport choices, measure selection and timeframe controls. Existing units, validation and inclusive end-date semantics remain intact.
- Milestones now carry stable IDs, original earned dates, criteria and the threshold-crossing activity. Health imports use their original completion dates. Tappable badge cards open with the native zoom transition on iOS 18+, with standard navigation on iOS 17. Original Shift medallions rotate in three dimensions on drag and have a back face, spring settling, Reduce Motion handling and an accessibility rotation action.
- Weather on Home, activity preparation and settings uses a shared presentation. Temperatures round to whole degrees in the user's weather unit format. Wind, rain and UV have distinct labels. Warnings are grouped, provider alerts remain linked, and Apple's official Weather mark is rendered with foreground contrast in both themes. Weather settings now has a current-conditions overview, location choice and city search.
- Run/walk/cycle preparation has a clearer heading, a neighbourhood-scale map without business POIs, GPS readiness on the map, weather, and an anchored Start action. Live recordings retain active time, distance, pace/speed, pause/resume, finish, recovery and discard paths. Weather settings do not start route recording.
- Coach navigation hides the tab bar to give the composer its own bottom inset. The composer is rounded with a clear send action, chat is less card-heavy, prompts are grouped, and the response waiting state uses understated animated dots. The prompt now asks for a direct answer, short practical advice and one useful next step, without stock praise, slogans or repetitive closing offers. Responses still run on device through Foundation Models.
- The planner uses interactive keyboard dismissal and an explicit focus binding, plus Return-to-finish. No keyboard-dismiss button was added. "Fill in my plan" explains what the action does. The later stages expose one leading back action which returns to the previous stage; the first stage retains normal navigation back. Stage changes reset scroll position.
- AI no longer generates clock times. A deterministic parser accepts explicitly written day/time ranges, preserves AM/PM, and leaves ambiguous/open-ended availability for selection. Weekday additions default to 18:00–20:00 and weekend additions to 09:00–11:00; named shortcuts apply those ranges only when chosen. Explicit overnight preferences are not silently reinterpreted as daytime.

## Optional Apple Calendar checking

The planner offers "Avoid Calendar clashes". Toggling it asks for EventKit full event access on iOS 17+ using `NSCalendarsFullAccessUsageDescription`, because reading busy times requires that permission. Shift uses this access only to read; it does not create, edit or delete Apple Calendar events. The switch is scoped to the current planner and does not silently turn itself on on later visits.

The seven-day query expands recurring events through EventKit, respects all-day event dates and filters canceled, explicitly free and declined events. Busy intervals are clipped and merged, combined with uncompleted Shift sessions, and passed to the existing deterministic weather/availability planner. Event titles, locations, notes and attendee data are not put into AI prompts, cloud mutations, Watch context or widget storage. Before saving, Shift reloads its sessions and re-queries Calendar. New overlaps stop saving and ask the user to find times again. Revoked permission stops a checked save rather than claiming the calendar was checked. Denial leaves manual/Shift-only planning available.

Accepted sessions still use `EnduranceService.schedule`: account ownership, atomic local mutations, private sync, Watch/widget summaries and opted-in reminders all use the existing paths. No new database migration or Calendar permission on Watch is needed. WeatherKit entitlements and existing deep links are retained.

Apple reference: [Accessing Calendar using EventKit](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui).

## Validation

- Generic iOS Simulator build succeeded, compiling the iPhone, Watch and widget targets.
- 82 native XCTest cases passed with the actual shared models, persistence, scheduling and notification policies. Seven new cases cover historical milestone dates/owners, cumulative thresholds and future records, explicit AM/PM and 24-hour availability, ambiguous-time rejection, merged busy ranges/adjacent sessions and a 25-hour London fallback day.
- Native SwiftUI previews render the actual goal controls, conditions and badge components in light/dark variants. This host is macOS; it does not substitute for iPhone interaction or large-text checks.
- `git diff --check` passed. No customer Health library or personal Calendar was used as test data.
- The prior iOS simulator runtime/test-manager blockage remains a limit: actual keyboard swipes, native zoom/drag gestures, hardware AI phrasing, permission prompts, GPS, Watch and live Calendar/Health responses need a physical-device check. They are not reported as runtime-tested here.

Artifacts: `build/testflight-2.1.0-23/` (ignored): native test log, simulator build log, rendered previews and release/Apple processing evidence.

## Release

Final release: 2.1.0 (23). The last visual review corrected low-contrast weather symbols in light mode using an explicit palette. Planner inputs are disabled during generation/save, accepted suggestions are captured before awaiting a save, and Calendar permission is checked again after reading busy times.

The repeated native suite passed all 82 cases after these final changes. Archive, upload and Apple processing confirmation follow below.

The final Release archive succeeded. All four bundles report 2.1.0 (23); deep/strict signature verification passed. The signed iPhone entitlement and embedded provisioning profile retain WeatherKit=true, phone and Watch retain the `shift` scheme, and the archived app includes the Calendar usage description. Source fingerprints match the final tested source. Upload/processing confirmation is recorded separately.

Upload succeeded at 01:32 GMT on 25 October 2026. Apple listed 2.1.0 (23) in Build Uploads as Processing. Final processing and tester access are verified below when complete.

App Store Connect's browser session expired during the final processing check and redirected to Apple sign-in. Xcode's upload log confirms success; the last authenticated dashboard read showed build 23 as Processing, with build UUID `62dff14d-a291-4d20-a5d2-187bc215a972`. Browser sign-in is required to verify Complete/internal tester access and save the prepared What to Test notes. These steps must not be reported as finished until verified in the dashboard.
