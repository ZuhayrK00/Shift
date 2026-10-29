# Shift 2.1.1 (25)

29 October 2026, Europe/London.

## Change

Adds opt-in Pro forecast monitoring with reschedule suggestions that require explicit confirmation. Availability, the original planning week and time zone, fresh full-session hourly weather, Shift conflicts and optional Apple Calendar busy times constrain replacements. A confirmed move keeps the same session identity and updates reminders, Watch agenda and widgets. Existing sessions can opt in through weather preferences. Optional forecast-change notifications and opportunistic iOS background refresh are included.

Details and device-testing limits are in [the feature notes](weather-rescheduling.md). No database migration or new subscription product is needed.

## Verification

- All 39 focused native XCTest cases passed again during release preparation.
- The final Release archive succeeded. iPhone, widget, Watch and complication bundles all report 2.1.1 (25).
- Deep/strict code-signature verification passed. Signed app and provisioning profile retain WeatherKit. Calendar purpose text, phone URL scheme, fetch/location background modes and the registered weather-review identifier were checked in the archive.
- Simulator-only capture fixtures are excluded from the archived executable. Source fingerprints match the archived source.
- The hosted privacy policy was retrieved and verified to include the rounded planning-area lookup point and optional forecast monitoring.

## Upload and submission

Xcode confirmed Upload succeeded, Uploaded package is processing and EXPORT SUCCEEDED at 22:15 GMT on 29 October 2026. Apple made build 25 selectable, and it was attached to version 2.1.1. The existing Team (Expo) internal TestFlight group has one tester, and What to Test notes were saved with Apple’s Saved confirmation.

The new version's description, release notes and reviewer navigation instructions are saved. Existing iPhone, iPad and Watch screenshots were inherited and checked. Automatically release this version is selected; all-user release is selected and the existing rating is retained. Reviewer sign-in/contact details were retained.

The final submission was accepted on 29 October 2026 at 22:23 GMT. App Review shows **Waiting for Review** for **2.1.1 (25)**, submission ID `63e80724-d4d0-4a49-8594-5b2d88937249`. Automatic release after approval is selected, rather than manual or scheduled release. No additional developer release click is required if Apple approves the submission and distribution completes.

Local archive logs, upload receipt, metadata and verification evidence are in the ignored build/app-store-2.1.1-25 directory. Public availability is not implied by upload or review submission.
