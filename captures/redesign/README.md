# Current iOS 27 UI captures

Captured September 27, 2026 from the native app on an iPhone 16 Pro simulator, iOS 27.0 (24A434), with Xcode 27. Production deployment minimum remains iOS 26.

These are real rendered SwiftUI screens, using 15 generated sample screenshots. The capture project is isolated; it replaces PhotoKit and disables index persistence. No personal Photos library is used. AI source is retained but inference is not exercised. These images do not verify Photos permissions, OCR, AI, iCloud, deletion, or persistence after relaunch.

- `light.png`, `dark.png`: full library, icon filters, result count, floating search circle.
- `search-expanded.png`: tapped native search circle expanded, before typing.
- `search-results.png`: typed “weekend,” keyboard visible, four matches and live count.
- `search.png`: launched directly into the same search state.
- `gallery.png`: full-library viewer and bottom thumbnail gallery.
- `gallery-filtered.png`, `gallery-swiped.png`: result-limited gallery before/after thumbnail selection and a page swipe.
- `tags.png`, `tag-list.png`: tag management with leading icons.
- `icon-collection.png`: searchable catalog of 64 named symbols; all asserted available in this runtime.

`light/dark/search/tags/gallery` are simctl captures. Other images are XCTest screenshot attachments from the passing reproducible run. `library-light.png` is the UI test's starting library screenshot. `evidence.json` records image/source hashes and validation scope.

Production app build and 15 core tests pass. Both native UI tests pass: search expansion/filter/count/gallery interactions; icon selection/tag edit/cancel/filter preservation. Run `bash scripts/run-ui-tests.sh SIMULATOR_UDID NEW_OUTPUT_DIRECTORY` to reproduce with XcodeGen. Capture its installed app with `bash scripts/capture-simulator.sh SIMULATOR_UDID OUTPUT_DIRECTORY`.
