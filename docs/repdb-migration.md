# RepDB catalogue migration — 29 September 2026

## Production verification

- 601 selectable RepDB exercises; 1,056 verified flat-style WebP assets in the `repdb-exercise-images` Supabase bucket.
- All 1,290 original built-in records removed. No production exercise links to the former R2/ExerciseDB artwork.
- All 198 logged sets and 30 plan-exercise records preserved; zero missing exercise references. No exercise goals existed at migration time.
- 1,290 compatibility redirects protect uploads from older/offline clients. 103 confirmed equivalents link to the current library. Other IDs link to hidden history-only placeholders, not guessed substitutions.
- History-only placeholders contain no old artwork, descriptions, how-to instructions or equipment metadata. Only movement labels already referenced by user records are retained; unused placeholders have a generic label.
- Temporary import table and temporary Storage upload policy removed after import. Existing private avatar/progress-photo buckets were not changed.

## App changes

The selectable library, workout picker, curated programs and AI generator use the current catalogue. Exercise detail shows anatomical primary/supporting muscles, difficulty, equipment, instructions and form tips. Explicit bench setup requirements are listed separately from the primary implement.

Start/peak poses cross-fade only on detail surfaces. Animation pauses when inactive, respects Reduce Motion and has a pause button. Thumbnails do not animate. Retired GIF decoding/raw-data caching has been removed.

Catalogue updates rewrite local plan/history/goal references and queued payloads atomically. Upgrade refresh bypasses the ordinary six-hour interval. Local redirect lookups protect delayed Watch actions; the phone sends refreshed Watch context after reference/user sync.

For saved-plan variants without a confirmed equivalent, the editor offers an explicit replacement picker. Replacement retains sets, repetitions, rest and grouping, clears the old target load and leaves completed workout history unchanged.

Equipment-dependent recommendations recognise the new machine/EZ-bar vocabulary. The plate calculator is available for loadable bars, not cable stacks or fixed dumbbells. Plan muscle chips reflect all primary targets rather than just the first muscle listed by the source.

## Verification

- 179 automated tests passed with zero failures, including atomic reference/queue remapping, custom-exercise preservation, history isolation during plan replacements, primary muscle targeting and loadable-bar detection.
- The simulator displayed the hosted WebP illustrations, exercise instructions and regenerated review-account plans. Screenshots are saved in `~/Documents/Shift RepDB Review`.
- The paired Watch simulator launches; its dedicated free review account correctly displays the Pro requirement. This is not verification of a real paid entitlement or physical-device background sync.
- Build 2.0.10 (16) was signed with stable Xcode, uploaded successfully and finished processing. App Store Connect shows it as Testing in the existing internal Team (Expo) group.
- Main is pushed and GitHub Pages has deployed the updated legal/website attribution. Both public policy pages were checked after deployment.
- Old iPhone/iPad listing screenshots were replaced with verified captures of the new catalogue. Copies and App Store status captures are saved in `~/Documents/Shift RepDB Review`.
- Content Rights is completed. On 30 September 2026 at 12:27 PM, build 16, the Shift Pro subscription group, Shift Pro Monthly and Shift Pro Yearly were submitted together to Apple. All four items show Waiting for Review. Submission ID: `487f2206-390d-4f16-9e38-aeca80ae0288`. Reviewer account access and licence notes are configured. Manual release remains selected; submission does not publish the app.
- App Store Connect Business was checked before submission: Paid Apps Agreement, Free Apps Agreement, bank account, both listed U.S. tax forms, Digital Services Act and Model Reporting Rules for Digital Platforms all show Active. No financial details or declarations were changed.
- The owner reported testing the new build successfully and authorised submission. Physical paid-entitlement/background-sync testing was not independently performed by the agent.
- On 30 September, the retired Cloudflare R2 `exercise-images` bucket was emptied through the dashboard and its public development URL disabled. A refreshed Objects view is empty; former GIF URLs return HTTP 401 after access was disabled. The new Supabase WebP image endpoint still returns HTTP 200. The empty bucket configuration was retained; no unrelated buckets or user storage were changed. Deleted objects cannot be restored through this operation.

## Provenance and licence

Source: [RepDB official repository](https://github.com/RepDB/exercise-dataset), pinned revision `9ed9357f09c7566ea0256c57ebd6374ebb8b575e`.

[Free Tier Licence v1.0](https://github.com/RepDB/exercise-dataset/blob/9ed9357f09c7566ea0256c57ebd6374ebb8b575e/LICENSE-DATA.md) permits commercial in-app use with attribution. Visible attribution links were added to Settings, exercise details and website footers. Only free flat images are used, not paid preview animations. Images are not supplied to the plan-generation model.

The complete source/import content is deliberately excluded from Git: the licence does not permit republishing a dataset or a standalone dataset API. Reference/import scripts stage files in the ignored `migration-preparation/repdb` directory, and require explicit steps for production writes.

## Remaining launch checks

1. Await Apple's review of the four submitted items and address any reviewer questions or requested changes.
2. After approval, explicitly release the app manually when the owner is ready. No public release was performed as part of this submission.

Submission confirmation and Waiting for Review captures are saved alongside the review screenshots in `~/Documents/Shift RepDB Review`.

Private local preparation records contain a pre-migration record-ID/reference backup and the production verification results. They are not included in the repository or exposed by the app.
