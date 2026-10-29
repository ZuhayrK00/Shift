# Shift Endurance Pro — 2.1.0 (24)

This release adds the Endurance split to the existing monthly/yearly Shift Pro subscription. No new subscription products or prices are introduced.

## Included access

| Feature | Free | Shift Pro |
| --- | --- | --- |
| Run, walk and cycle recording, GPS maps and activity history | Yes | Yes |
| Apple Health imports, basic goals, personal bests and milestones | Yes | Yes |
| Current weather, manual calendar scheduling, editing saved sessions and reminders | Yes | Yes |
| Complete generated week, including availability, weather and optional Apple Calendar checks | One saved week per account | Continued planning |
| On-device Endurance coach | No | Yes, on supported Apple Intelligence devices |
| New training plan library schedules and six-month progress chart | No | Yes |
| Existing saved training plans and generated sessions | Remain available | Yes |
| Watch and widgets | Existing Pro policy | Yes |

The week planner remains usable through its manual controls on devices without Apple Intelligence. Pro benefits list only features available in this build; future interval, adaptive and hybrid training features are not advertised.

## Free week integrity

Migration `029_endurance_week_preview.sql` adds an owner-readable receipt and `save_endurance_week_preview(uuid,jsonb)`. The server saves every session and claims the account's allowance in one transaction, with an account-specific transaction lock. Empty/invalid/failed saves do not claim it. Repeating a request returns the original receipt and its current session rows. Deleting a plan, changing devices or reinstalling does not reset usage. Account deletion cascades to the receipt.

Receipt writes are unavailable directly to authenticated clients. Anonymous access is denied. The app caches usage per account, and local hydration preserves edits, pending changes and deletions without creating duplicate outbound inserts. StoreKit entitlements are freshly verified at paid generation/chat/template operations. Manual scheduling and access to saved sessions are deliberately outside the paid boundary.

The new paywall describes Strength and Endurance together, retains Apple's current prices and offer eligibility, and keeps restore/legal controls accessible when product loading fails. Successful purchases and restores update the visible gates. Data exports include the cached free-week record; the privacy policy source describes its purpose and retention.

## Verification

- Generic iOS Simulator build including Watch and extensions passed.
- 92 native source tests passed, including preview ownership, all seven sessions, invalid weeks, failed transaction rollback, lost-response recovery, repeat hydration, pending deletions and entitlement expiry.
- Disposable PostgreSQL-compatible PGlite migration checks passed: full five-session save, rollback, duplicate claim, idempotency, owner isolation, direct-write denial, anonymous denial, edit/deletion preservation and account deletion.
- Production Supabase catalog verified: RLS enabled, authenticated owner SELECT only, no direct writes, no anonymous reads/execute, secured save RPC, one owner policy. Screenshot: `build/testflight-2.1.0-24/preview-schema.png`.
- Actual SwiftUI benefits, free-week note and upgrade components rendered and reviewed in light/dark. Native macOS rendering is not an iPhone interaction or Dynamic Type runtime test.
- `git diff --check` passed.

Physical-device checks still needed after installing TestFlight: a free-account preview save, second-week paywall, restore/purchase using Apple's test environment, Calendar/weather permission flow, notifications and Watch/widget updates. No actual subscription purchase was made for verification.

## Release status

Archive succeeded. Phone, Watch, widget and complication all report 2.1.0 (24). Deep signature verification, WeatherKit entitlement/profile, Calendar purpose text and phone/Watch `shift` URL schemes passed. Source hashes did not change during archive.

After the user refreshed the Xcode Apple account session, the verified archive uploaded successfully on 27 October 2026 at 22:00 UTC. Xcode reported “Upload succeeded”, “Uploaded package is processing” and “EXPORT SUCCEEDED”. The phone, Watch and extensions are version 2.1.0 (24). Apple processing completion and tester availability were not independently confirmed, in line with the request to finish with upload confirmation only. The upload log is saved in `build/testflight-2.1.0-24/upload.log`.

## App Store review follow-up

The same build was submitted for public review. On 28 October 2026, Apple requested WeatherKit attribution confirmation under guideline 5.2.5. A physical-iPhone recording showing the existing Apple Weather mark and Data sources link, with navigation instructions, was attached before resubmitting the same build.

On 29 October 2026 (Europe/London), App Store Connect confirmed **Pending Developer Release** for version 2.1.0, build 24. The **Release This Version** control was enabled, manual release was selected, and publication was not triggered during the status check. Approval is confirmed; public availability must be checked separately after manual release.

The repository also contains simulator-only capture helpers added after the build-24 archive for App Store artwork and promo photography. These require both `SHIFT_STORE_CAPTURE` and a simulator target and are excluded from normal builds. Local exports and review recordings are not source assets.
