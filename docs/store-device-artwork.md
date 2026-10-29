# iPad and Apple Watch App Store artwork

Prepared 29 October 2026 for the 2.1.1 listing. The submitted production binary remains 2.1.1 (25); capture helpers are simulator-only and do not change the release features.

## Captures

The dedicated **Shift Launch iPad Pro 13** simulator runs iPadOS 26.5 and produces 2064 × 2752 native images. The dedicated **Shift Store Capture Watch** simulator is an Apple Watch Series 11 46 mm running watchOS 27 and produces 416 × 496 images.

Use `SHIFT_STORE_CAPTURE` at compile time and `--store-capture --capture-screen <screen>` at launch. The capture account is a local, fictional Alex Morgan. The backend is unreachable in capture mode; no customer data is used. Seeding clears the dedicated simulator's local training tables, so use only the named capture simulators.

The iPad set includes Strength Today, Endurance Today, an active gym workout, a mapped run, goals, progress and milestones, the shared training calendar, a generated week and confirmed weather-change suggestions. The local seed contains 64 completed gym sessions, 84 outdoor activities, four gym plans, 28 weight entries, three endurance goals and eight upcoming sessions.

The Watch set includes its home screen, a two-exercise gym session, the actual set logger and an active run with distance, elapsed time, pace and heart rate. Its `home`, `gym`, `sets` and `recording` launch entries use the existing native view bodies with fictional model state. No replacement UI is rendered.

## Artwork and review

`scripts/render-store-device-artwork.cjs` composes the native screenshots into nine iPad images with a dark, teal/violet background and fully visible tablet frames. Watch upload images stay full-canvas native screenshots for readability. A separate labeled Watch presentation board accompanies the review preview.

Run the renderer from the repository root with Sharp available through `SHARP_MODULE_PATH`. Generated assets are ignored under `output/app-store-2.1.1-devices/`:

- `raw/ipad/` and `raw/watch/`: original native captures.
- `artwork/ipad/`: nine upload images, 2064 × 2752, opaque RGB PNG.
- `artwork/watch/`: four upload images, 416 × 496, opaque RGB PNG.
- `preview.html`: full-resolution review gallery.
- `ipad-contact-sheet.png` and `watch-contact-sheet.png`: review boards.
- `capture-manifest.json`: source dimensions, fictional-data provenance and raw capture SHA-256 hashes.

The first generated week is identified as free; continued planning, longer-term trends, forecast monitoring and Watch access retain the existing Pro disclosures. No swimming, automatic rescheduling or Watch route-map navigation is advertised.

Validation completed: native capture builds and a normal build without `SHIFT_STORE_CAPTURE` succeeded. The normal Watch binary excludes the new capture seed. All 13 upload PNGs have the expected dimensions, use opaque RGB, and the original capture hashes match the manifest. The complete iPad set and Watch presentation board were visually reviewed.

The user previously requested that new images be shown before upload. This new device set must be approved before replacing the inherited screenshots. At preparation time, 2.1.1 was Waiting for Review and its screenshot DropZone was disabled. Updating the submitted version requires removing it from review, replacing the iPad/Watch images, and resubmitting with automatic release after approval retained. Do not confuse prepared local assets with uploaded or approved assets.
