# Shots

A small native iPhone screenshot organizer. SwiftUI, local AI, search, editable tags. No account, ads, subscription, API key, or third-party app dependency.

## Run on your iPhone

1. Open **Shots.xcodeproj** in **Xcode 26 or later** on your Mac.
2. Select the **Shots** target → **Signing & Capabilities** → choose your Apple development team. Change `com.calum.shots` if Xcode asks for a unique bundle identifier.
3. Choose your connected iPhone running **iOS 26 or later**, enable Developer Mode if prompted, and press **Run**.
4. Allow Photos access. Automatic tags require an Apple Intelligence-compatible iPhone, with Apple Intelligence enabled and its model downloaded.

The private source repository is [0x63616c/shots](https://github.com/0x63616c/shots). **Shots 1.0 (4)** is available in the existing internal TestFlight group, including description-first category discovery, Analysis details and Favorites, plus the earlier scan and header fixes. The production target builds locally with Xcode 27; native UI is verified on an iOS 27 simulator with a synthetic library. Physical-device Photos and AI validation remains open; see `REVIEW.md`.

## Local release

There is no CI or upload-on-push automation. On this Mac:

```sh
just test               # Portable core + release-tool tests
just verify             # Also native UI tests + unsigned production Release build
just release            # Full validation → signed archive → audited IPA → TestFlight upload/read-back
just release-status 2   # Read-back only; safe after an uncertain upload
```

`just release` requires a clean committed Git tree, Xcode 27, XcodeGen, Python 3 with `cryptography`, and the existing Apple Distribution identity / “Shots App Store” profile in the local Keychain. Use a dedicated iOS 26+ simulator named **Shots**, or set `SHOTS_SIMULATOR_UDID`; the isolated fixture does not touch personal Photos. Calum's **Shots iOS 27** simulator is already set up.

App Store Connect credentials are injected by the sibling `world-wide-webb/scripts/secrets.sh` wrapper. On another machine set `SHOTS_SECRETS_WRAPPER` or supply `APP_STORE_CONNECT_API__KEY_ID`, `APP_STORE_CONNECT_API__ISSUER_ID`, and `APP_STORE_CONNECT_API__P8_CONTENT` securely. Never put their values in Git. Install tooling separately if missing (`brew install just xcodegen`; use a Python environment with `cryptography`).

The command selects a fresh integer build number above local, preserved, and Apple builds without changing project source. It preserves artifacts/evidence in ignored `release/testflight-YYYYMMDD-buildN/`, uses a private temporary upload key, and verifies Apple processing plus availability to the existing **Calum** internal group/tester. Build/test subprocesses receive a restricted environment, not the decrypted secrets vault. It neither pushes Git nor submits an external beta/public App Store version. If an upload fails or times out, inspect `just release-status N`: a failed command can still have delivered the build. Unresolved upload receipts block subsequent publishing; a successful read-back (or definitive Apple processing rejection) resolves the receipt.

## Use

- Your existing screenshots appear in a three-column grid, newest first, with a numeric result count and the title at the top left. In **•••**, choose **Continuous grid** or **Grouped by day**; the choice is remembered, and date headers stick while scrolling. The grid reuses visible cells for large libraries.
- Tap the floating Liquid Glass search circle to expand it. Search reads screenshot text, saved descriptions, short AI titles, visual labels, and assigned tag names. Multiple words must all match. Tap a tag to narrow the results.
- Tap the heart in the screenshot viewer to favorite it. **Favorites** in the library filters your saved picks; a thumbnail’s long-press menu also offers Favorite/Unfavorite. Favorites are your choice and survive AI rescans.
- Tap a screenshot for the full-screen viewer. Swipe between the current results or tap the bottom thumbnail gallery; the open image stays centred in the strip, including at either end. Pinch/double-tap to zoom. Share and Tags are separate bottom buttons. The viewer reuses pages instead of building a page for every result. Its menu contains **Analysis details**, **Rescan**, and **Delete from Photos**. Analysis details shows the saved description, whether it used the image or extracted text, analysis date, full extracted text, visual labels, and any error.
- Rescan one image from its **••• → Rescan** menu or by long-pressing its thumbnail. Use the library’s **••• → Rescan all**, or **Select** then the rescan arrow, for multiple images.
- **Hide** is available on a thumbnail’s long-press menu, in the viewer menu, and for a selection. Hidden items leave normal search and automatic scanning, and appear under **••• → Hidden screenshots**. Choose **Unhide** to restore them. This is an app-local filter, not the locked Apple Photos Hidden album; it never deletes the original.
- In **Tags**, tap a tag to edit its name and icon, tap **+** to create one, and swipe to delete. Renaming keeps assignments. Deleting a tag never deletes screenshots. A searchable collection of 64 SF Symbols appears beside labels; the same named vocabulary informs local AI tagging.
- Changing the tag list automatically re-evaluates AI assignments using saved descriptions and OCR. Rescanning rereads the image. Both preserve your manual tag additions/removals.
- **Settings** has appearance, iCloud downloads, **Continue scan in background**, the last scan timing, and an explanation if automatic tags are unavailable. Dark appearance uses a black background.

Scanning saves searchable text first, then describes screenshots in a separate foreground pass. On iOS 27 with vision support, the local Apple model sees the screenshot itself; iOS 26 uses extracted text and general image labels. Descriptions are factual summaries of format, source, content and key details, without guessing relationships or why you saved something. They are saved independently, searchable, and reusable when categories change.

Categories are discovered from a bounded sample across the library’s date range. Discovery first runs after a 32-description batch (or at the end of a smaller scan), and tagging follows in batches so early results appear before the full description pass finishes. Later discovery adds categories while preserving existing names/IDs. Untouched starter categories can be retired during migration; manually edited categories and assignments are preserved. Deleted/renamed category names are remembered so discovery does not recreate them. Libraries without useful categories are revisited as more descriptions arrive; established categories are reconsidered after 100 additional descriptions, at bounded milestones during a large scan. Rescan all and upgrading multiple text-based descriptions to image analysis also reconsider categories. A refused image description can fall back once to extracted text; successful fallbacks stay saved until an explicit rescan. Discovery can retry smaller samples within seven requests when an individual sample is refused. Up to eight categories can be added per discovery, within the 32-tag limit.

The progress bar identifies indexing, describing, discovering categories, or tagging, with completed/total counts, active elapsed time, and approximate time remaining after three completions. Pause/resume preserves saved work. **Settings → Last scan** retains the run’s elapsed time and image loading, Vision, and descriptions/tags breakdown. New screenshots are picked up when Photos changes or you reopen the app. Pull down to refresh.

Unrelated Photos updates and unchanged screenshot metadata do not interrupt indexing. “Paused” means an actual user/system/storage pause, not a transient refresh or scan handover. Grouped headers use adjacent opaque coverage throughout the date-to-date push-off transition, including partial rows.

Normally scanning pauses when you leave Shots. While work remains, tap **Settings → Continue scan in background** to request continuation for this scan only. iOS controls admission and duration and provides system progress/cancellation. Background work reads text using CPU-only Vision; automatic tags finish when Shots is open. There is no always-on Photos watcher. Force-quitting, cancellation, expiration, or device conditions can stop the scan. Completed work is checkpointed and resumes on return.

## Local by design

- PhotoKit accesses original screenshots in Apple Photos. Shots does not maintain another full-resolution photo library.
- Apple Vision reads text and general image labels locally. Apple Foundation Models describes screenshots locally, discovers categories from your library, and assigns tags from that editable list.
- OCR, titles, tags, and asset references are stored in an atomic, protected file under Application Support, excluded from backup. Appearance and download preferences use this app's UserDefaults.
- There is no AI server, analytics SDK, account, network API, or cloud fallback. iCloud Photos may download images that are not already on your phone; this can be disabled in Settings. Analysis still stays local.
- Uninstalling removes Shots' tags/index. It leaves originals in Photos. Deleting a screenshot explicitly through Shots deletes its Photos original and can sync that deletion through iCloud Photos.

## Scope and limits

- Up to 32 editable tags; AI chooses up to four per screenshot. Manual assignment can use any number of your tags.
- Search is keyword search, not semantic/vector search.
- OCR indexes all recognized text. Descriptions use the screenshot image when supported, plus up to 3,000 UTF-8 bytes of extracted text; text-only fallback can miss visual context. Descriptions are capped at 600 characters. Category discovery samples up to 32 distinct descriptions (retaining duplicate occurrence counts) within a 5,000-byte input budget. Tag assignment uses the saved description plus up to 1,400 bytes of OCR. Rare categories and later content in long screenshots may be missed; inspect Analysis details and correct tags when needed.
- Failed AI analysis keeps successful OCR searchable and can be retried. The app also works with OCR/manual tags when the model is unavailable.
- Photos marked as screenshots are included; arbitrary downloaded images and full-page PDF captures are not automatically imported.
- Sharing exports the displayed rendered image, bounded to 2400×4000 pixels; originals are unchanged.
- Background text indexing is opt-in and best-effort, not a guarantee that all 15,000 images will finish while the app is closed. AI tagging remains foreground-only. Checkpoints occur after 100 analysis/tagging operations or 30 seconds at an operation boundary, at phase boundaries, and on orderly pause/exit. Unsaved work may be reprocessed after force-quit or OS termination.
- Tags belong to this app's local index, not Apple Photos keywords or albums. No cross-device tag sync.

## Project map

| Path | Purpose |
| --- | --- |
| `SPEC.md` | Governing goal and acceptance checklist |
| `Shots/Core` | Portable models, tag rules, search |
| `Shots/Services` | Photos access, Vision, Foundation Models, protected persistence |
| `Shots/LibraryStore.swift` | Index/scan coordination, manual edits, lifecycle |
| `Shots/Views` | Minimal SwiftUI screens and zoom viewer |
| `Shots/Assets.xcassets` | Black-and-white app icon |
| `Tests` | Executable core tests |
| `REVIEW.md` | Spec review, checks performed, device checks remaining |

## Verify on a Mac

```sh
swift test
xcodebuild -project Shots.xcodeproj -scheme Shots \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The Swift package tests only the portable core. The iOS application is the Xcode project. Test local AI on a compatible physical iPhone; model availability in a simulator is not a substitute.

## Native UI evidence

See `captures/followup-20261004/` for verified date-header handoffs and uninterrupted refresh scanning, and `captures/performance-update/` for the earlier 15,000-record grid/paging evidence. `captures/library-update/` and `captures/redesign/` preserve older revisions. These are real simulator captures using an isolated synthetic library, with Photos and persistence disconnected. The large fixture reuses 15 image designs across 15,000 unique records. UI-only captures do not prove OCR, AI inference, deletion, background execution, or index relaunch persistence. The separately labeled benchmark uses the real Vision and Foundation Models services on synthetic images.

Reproduce interaction tests with Xcode 27, XcodeGen, and a booted iOS 27 simulator:

```sh
bash scripts/run-ui-tests.sh SIMULATOR_UDID /private/tmp/shots-ui-check
```

The output directory must not already exist. The script makes an isolated fixture project, checks every catalog symbol at launch, and runs `UITests/RedesignUITests.swift`. Production sources and your Photos library are untouched. Screenshot attachments live in the resulting `UITests.xcresult`.

After installing the sample app with the UI test script, measure an unthrottled scan:

```sh
bash scripts/benchmark-simulator.sh SIMULATOR_UDID /private/tmp/shots-benchmark.json
```

This times 15 generated 600×1000 images in the simulator. It bypasses PhotoKit, iCloud, and index writes. AI availability is recorded in the report; simulator timings are not iPhone performance guarantees. The pause/resume UI test uses a deliberate 700ms sample-fetch delay for repeatability and is not used as the speed benchmark.
