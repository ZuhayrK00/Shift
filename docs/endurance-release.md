# Endurance v1

Strength and Endurance share the same account and profile. The mode menu beside the Shift heading on Today selects the available training tools. Endurance supports iPhone GPS recording for running, walking, and cycling; private route history; kilometre splits; distance/time/activity-count goals; and explicit Apple Health imports for the last 90 days.

## Deployment

`supabase/migrations/027_endurance.sql` was applied to the Shift Supabase project `dtzlfvuazdrgyyutjysm` through the SQL Editor on 24 October 2026. Both new tables were verified with RLS enabled, one owner policy each, authenticated access, and no anonymous SELECT access. The two tables cascade on account deletion. The migration is additive; no existing strength tables change.

Update App Store privacy disclosures for precise location, workout routes and fitness data before release. The in-repository privacy policy describes the new processing. Location is requested when the user enters recording, not at launch. Health routes are a separate opt-in in the import sheet.

Version 2.1.0 (17) was archived, code-signature verified, and successfully uploaded to App Store Connect for TestFlight on 24 October 2026. The app, widget, Watch app and complications all use the same version and build number. Apple finished processing it, and the build was verified in the existing **Team (Expo)** internal testing group with one invited tester. This upload does not submit an App Store release.

Version 2.1.0 (18) was also archived, code-signature verified and successfully uploaded on 24 October 2026 with the home-heading mode menu, compact page headers, persistent map-import preference and clearer import results described below. Apple finished processing it, and the build was verified in **Team (Expo)** with one invited tester.

Version 2.1.0 (19) was archived, code-signature verified and successfully uploaded on 24 October 2026 with the aligned home headers, glass mode selector and colour accents described below. Apple finished processing it, and the build was verified in **Team (Expo)** with one invited tester. Availability proof is saved in `build/testflight-2.1.0-19/ready.jpg`.

## Recording and storage

- Core Location supplies samples, MapKit displays the actual accepted points. Pauses and GPS gaps are separate polyline segments; no directions API or road snapping invents a path.
- Reject inaccurate, stale, out-of-order, implausibly fast and stationary samples. Elevation is a smoothed GPS estimate.
- Time continues while the screen is locked; use manual pause during stops. Auto-pause is not included.
- Checkpoints are SQLite records scoped to the signed-in user. Recovery after termination is paused at the last checkpoint, without counting unknown time. The user can resume, finish, or discard.
- Saving the finished activity and its sync mutation, and removing the draft, is one transaction. Save failures retain the recording.
- Activity and goal details use version-one Codable JSON in owner-scoped envelope rows. The existing FIFO mutation queue and complete-snapshot reconciliation preserve pending changes.
- Local and cloud deletion, data export, and weekly training goals include endurance records. Body and exercise goals remain available in Profile.

## Health imports

Import requests only workout read access, and route read access if selected. Record IDs are deterministic hashes of the account ID and workout UUID, so repeat imports are idempotent and separate accounts can import the same device workout independently. Shift-originated workouts are excluded. Reimport with route access can fill in a previously missing map without creating another activity. Imported distances and workout duration come from HealthKit, not recalculation from sampled routes. Imported splits are not fabricated when pause timing is unavailable. Imports do not run automatically, write to Apple Health, or delete the original Health workout.

Build 18 replaces the separate mode toggle with a home-heading menu and gives the main pages and import/editor sheets compact title rows. The map import switch uses the same control tint as Shift's other settings and is remembered locally for each account; deleting that account clears its preference. The import sheet shows how many Health activities are already saved. Import results distinguish new activities, added maps, already-imported workouts, missing route data, and Health returning no readable workouts. An empty route response does not rewrite a saved activity or claim a successful map update. Health read denial cannot be identified directly, so empty-result guidance avoids claiming that permission was refused.

Build 18 validation: the focused iOS 27 simulator run passed all 23 endurance tests with zero failures, including the new route-preference persistence/account-isolation and repeat-import/missing-map result checks. The simulator was shut down after the run. Real Health permissions and route imports still require device testing.

## Build 19 appearance

Both home screens use the same `TrainingModeHeader`, which owns its 44-point control height, 8-point top margin and 16-point bottom margin. Both hide the navigation bar with the same toolbar API. Endurance no longer adds a separate 20-point top inset, eliminating the 12-point vertical jump when changing modes.

The mode selector is a tinted glass capsule on iOS 26 and later, with a material fallback on earlier iOS versions and a solid surface when Reduce Transparency is enabled. Its popover shows violet Strength and teal Endurance choices with icons and a selected checkmark. Colour supplements the labels and selection state.

The shared light/dark palettes now use violet for primary actions and selections, with blue as the secondary chart accent. Endurance uses teal for activity actions, selected filters, route lines, goal progress and the selected tab. Backgrounds stay neutral; success, warning and destructive colours keep their existing meanings. Light and dark filled-button foreground/background pairs exceed 4.5:1 contrast. No storage, permissions or import behaviour changes in this appearance update.

Build 19 validation: the final simulator build succeeded for arm64 and x86_64, and the optimised iOS archive succeeded. Deep, strict code-signature verification passed. The app, widget, Watch app and complication bundle versions were checked as 2.1.0 (19). Workout and activity detail destinations explicitly keep their navigation bars visible when opened from the shared home header. The existing 23 endurance tests were not rerun for these appearance-only changes; their Build 18 results are recorded above. Visual/device checks remain in the release checklist below.

## Release verification on a physical iPhone

The test suite covers geometry, outlier filtering, pause and gap boundaries, active time, split interpolation, calendar goals, JSON, account scoping, idempotent records and transaction rollback. A simulator build cannot establish real-world GPS or battery performance.

Verification on 24 October 2026: the final simulator test build succeeded for arm64 and x86_64. The simulator executed all 18 initial endurance tests with zero failures, and the isolated database checks passed. The additional account-scoped Health import identity check passed as a standalone native Swift check. The broader suite stalled in the existing `testWarmupTapLogsImmediatelyWithoutConsumingWorkingSets` test; its retry stalled during simulator startup. A complete regression-suite pass and physical-device/UI validation are still outstanding.

`scripts/test-endurance-schema.sql` checks the actual migration, owner-only reads/writes, anonymous access denial, HealthKit uniqueness, input validation and account-deletion cascades in a disposable database. `scripts/test-endurance-schema.mjs` runs it in a fresh in-memory PGlite PostgreSQL engine when a working local server is unavailable; install the test tool outside the app and set `PGLITE_MODULE_PATH` if necessary.

Before shipping, verify a measured run/walk/ride with the screen locked; manual pause and resume; permission denial and reduced accuracy; airplane mode and later sync; GPS loss; app termination and draft recovery; sign-out/sign-in isolation; Health import with denied/partial/read-route permissions; repeated imports; and deletion on a second device. Check the interface in light/dark mode, Dynamic Type and small iPhone layouts.

Swimming, Watch-native endurance recording, automatic background Health imports, social feeds, route sharing, route planning, auto-pause, and competitive segments are outside this release.
