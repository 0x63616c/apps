# Acceptance and simplification review

## October 4 follow-up — shipped as TestFlight 1.0 (3)

- Fixed repeated scan interruption at its source: PhotoKit change tracking filters unrelated events; discovery happens before scan cancellation; unchanged snapshots are no-ops; stale refresh generations are rejected before/after checkpoint waits. Real pause reasons are separate from refresh/handover/task activity; the UI no longer infers “paused” from every temporary lack of a scan task.
- Grouped headers use next-header-origin push-off geometry: outgoing/incoming opaque backgrounds share an edge across partial/short sections, with one physical pixel of bleed for fractional seams. Metrics rebuild on width/type-size changes; scrolling retains binary section lookup and visible-cell reuse. Continuous mode remains compositional.
- **`just verify` passes:** 28 portable Swift tests, 15 release-tool tests, all 10 native UI flows, and unsigned production Release compilation. Final native result: `.release/verify-rzhmq1no/ui/UITests.xcresult`, read-back `Passed`, 10 passed / 0 failed / 0 skipped. Separate integrated unsigned-device Release compilation also passed.
- New native regressions use real store refreshes with identical synthetic Photos notifications every 500ms, asserting uninterrupted progress without pause flashes; genuine manual pause/resume still passes. Header pixels are checked at 320 fractional forward/reverse offsets across four handoffs, portrait/landscape, light/dark. Screenshots: `captures/followup-20261004/`. Physical-device/iCloud/background execution remains unverified.
- Earlier failures were in fixture instrumentation (controls installed before window attachment) and screenshot/appearance setup (simulator app-cropping orientation; ignored style launch argument). Tests now capture/normalize the device framebuffer, explicitly set fixture appearance, and confirm actual traits. They were not disabled or replaced with source-text checks.
- Private GitHub repository and `AGENTS.md` added as requested; no CI configured. `just release` validates locally, allocates a fresh number, signs/exports/audits the device IPA, uploads once, and verifies internal group/tester availability. Independent review findings were fixed: builds/tests no longer inherit the secret vault; remote numbering is rechecked; unresolved upload receipts block subsequent publishing. Executable orchestration tests cover those failure modes; re-review found no remaining blocking issues.
- After explicit user approval, **`just release` succeeded end-to-end** on clean revision `dc4ab851adc5b3a93f565ce8b675f63d9ac20e3c`: all 53 tests passed again, unsigned Release compilation passed, production archive/export and both signatures verified, device IPA/plist/fixture exclusions audited, and Apple upload succeeded without errors. Preserved artifact: `release/testflight-20261004-build3/export/Shots.ipa` (941044 bytes), SHA256 `7c1d8341729e2235dfb852fc9c052df9ec178d1ff1a4934f25ff80d9fe11d69a`.
- Build **1.0 (3)**, ID `959ccc48-97c9-46cf-8f60-23f7e434cf28`, is `VALID` / `IN_BETA_TESTING`, in the Calum internal group with the existing tester and automatic notifications enabled. Both the release command and a separate `just release-status 3` read-back confirmed `ready: true`. Release receipt: `release/testflight-20261004-build3/release.json`; fresh native suite: its `ui/UITests.xcresult`. No external/public submission or physical-device installation was performed; no `no-mistakes` pipeline pass is claimed.

## October 3 large-library revision — verified for TestFlight

- The gallery uses reusable native collection-view cells, opaque pinned date headers, numeric-only counts, and debounced search. Scan timer/stage changes are observed by a separate progress view, not the gallery. Record changes only reconfigure affected visible thumbnails; ordinary OCR updates do not reload the collection.
- The viewer uses an arithmetic paging layout with reusable cells and constant-time ID/index lookup. It keeps only the current and neighboring full-size images. The fixed-width filmstrip has margins so its first/last selection can also be centred. Share and Tags are separate toolbar items.
- OCR is indexed/checkpointed first, before the foreground AI enrichment phase. The model receives the complete bounded taxonomy once with compact integer IDs; returned indices are checked against that request's tags. Manual overrides and the version-1 index schema are unchanged. Incremental result/day caches avoid full regrouping per image; cold search document normalization runs off the main actor before the query is applied.
- Photos enumeration, resizing, and JPEG encoding run away from the UI. Index saves skip unchanged snapshots and occur after 100 operations or 30 seconds at operation boundaries, phase changes, and orderly exits. CPU-only compute devices are selected explicitly for every supported Vision stage, preventing background GPU use.
- Settings offers per-session, user-initiated `BGContinuedProcessingTask` continuation. Store lifecycle callbacks cancel/checkpoint before handing over to background OCR-only work. AI tagging and Photos discovery remain foreground-only. Expiration/cancellation and pause revoke the allowance after checkpointing. System progress is reported directly by the scan loop for the active phase, not by SwiftUI rendering.
- Production **Release simulator and unsigned iPhone builds pass** with Xcode 27 and minimum iOS 26. Build outputs are under the approved OpenCode temporary directory: `shots-performance-build-20261003` and `shots-performance-device-20261003`.
- **23 portable tests and all 8 native UI flows pass**, with zero failures in the final fresh fixture, `shots-native-ui-20261003-ready-4/UITests.xcresult`. This covers three-column visibility, pinned headers, numeric counts, 15,000-image first/last paging and filmstrip centring, actual Share/Tags actions, search, hide/unhide, icon editing, and phase-aware pause/resume. `captures/performance-update/` preserves the key native screenshots. Compilation and synthetic UI tests are not proof of on-device background runtime or performance with the user's real 15,000-image Photos library.
- The earlier integrated run caught a real compositional-layout sizing bug: the modern repeating-subitem API retained full-width item dimensions. Items now use explicit square dimensions, and the three-column regression passes. A share-sheet dismissal problem in the test was also corrected; the final suite opens the system share sheet and the separate Tags action successfully.
- Signed production **1.0 (2)** archived and exported with the existing Apple Distribution identity/profile. Its signature, bundle/version/minimum OS, background registration plist, non-exempt encryption declaration, and absence of synthetic-fixture markers were verified. Preserved IPA: `release/testflight-20261003-build2/Shots.ipa`, SHA256 `d1a074036bd542ecc9162ee0c0c4eb866ad518dc722d7dcf0e04641f0c9da1e6`. **TestFlight distribution verified:** build `a141671b-5c55-43be-a69c-08ef08dced28` is `VALID` and `IN_BETA_TESTING`, belongs to the Calum internal group, has automatic notifications enabled, and that group contains the existing tester. No external beta or public App Store submission was made.
- Current unthrottled synthetic benchmark: **15 images in 36.39 seconds**, versus the historical 62.75-second run (about 42% less wall time). Actual local AI was available, all 15 completed, zero failures. Raw data: `captures/performance-update/benchmark.json`. Scope remains simulator-generated 600×1000 images, no PhotoKit/iCloud/index writes; this is not a speed guarantee on the user's iPhone. Stage timers include awaiting queued/prefetched work and can overlap, so their sum can exceed wall elapsed time.
- The automatic `no-mistakes` Git pipeline could not run because this recovered directory is not a Git repository (`no-mistakes axi` returned that error). No Git repository, branch, PR, or remote was invented. Independent code review, portable/native tests, Release compilation, archive/export, and signed-artifact checks were performed instead; this is not a `no-mistakes` pass.

## Status

Current UI revision verified on macOS with Xcode 27 and iOS 27.0 (September 27, 2026). The production simulator target builds; 18 portable core tests pass. Four native UI interaction flows pass across the initial suite and the focused scan rerun. Screenshots use an isolated synthetic library. **Real Photos/OCR/AI lifecycle, device signing, and physical-device behavior remain unverified.** The historical source review below is retained with these updated results.

## Acceptance mapping

| Requirement | Implementation / review |
| --- | --- |
| Native Swift, local AI, no premium | SwiftUI + PhotoKit + Vision + FoundationModels; no third-party runtime dependencies, paywalls, analytics, or API keys |
| Existing screenshots; originals stay in Photos | Screenshot subtype fetch; asset references in local index; originals downloaded only through PhotoKit when enabled |
| Grid, search, tag filters | Three columns, two-point gutters, no tile captions; combined all-word/case/accent-insensitive search and All/Untagged/tag filters |
| Editable fixed taxonomy; multiple tags | Stable IDs, normalized duplicate-name validation, create/rename/delete, individual/batch assignments; output IDs intersected with allowed IDs |
| Preserve manual edits on rescan | Separate manual inclusion/exclusion sets; current record reread after OCR/model awaits |
| Single/selected/all rescans | Metadata invalidation and cancellable serial scan; tag-list edits reuse recognized text |
| Detail, zoom, share, deletion | Full-screen paging viewer, bottom thumbnail strip, native toolbars, pinch/double-tap zoom, system share UI, explicit deletion confirmation followed by Photos API |
| Backlog, new screenshots, interrupted work | First scan plus PhotoKit change observation and active-scene refresh; checkpoint every ten processed items and at scan exit |
| Denied/limited/cloud/empty/failure states | Permission action, limited picker, iCloud switch, empty views, load retry, visible AI-unavailable action, retained OCR on AI failure |
| Protected persistence | Atomic writes; protected local file; backup excluded; version guard; corrupt/unreadable files not reset or overwritten |
| Light/dark/black/minimal icon | System default plus appearance picker; black dark canvas; opaque black icon with white frame |
| Accessibility | Named icon actions, scalable labels, selected-state announcements, native controls; VoiceOver/device check still pending |

## Simplification pass

- One home screen. No tab bar, dashboard, cards, captions, AI chat, onboarding tour, billing, or account UI.
- Search is hidden until Photos access and the index are ready.
- Selection controls appear only during selection.
- Secondary actions live in the overflow menu or native sheets.
- Detail view exposes only close, more, share, and tags.
- Settings has appearance and iCloud downloads. AI help appears only when needed.
- Scan progress disappears when work is finished. Failure explanations are retained because they help resolve a real problem.
- The independent review found no further structural UI removal that would preserve discoverability and function.

## Correctness fixes from review

- Fixed an AI prompt string syntax error found by the Swift parser.
- Protected scan cancellation against overlapping lifecycle calls clearing a newer task.
- Cleared stale progress when no scan candidates remain, including paused/removed-library cases.
- Blocked metadata mutation until a saved index loads successfully; added Retry without destroying the file.
- Kept storage failure messages from being replaced by lower-priority scan messages.
- Surfaced unavailable Apple Intelligence on the home screen with a compact link to its explanation.
- Cached normalized search documents, invalidated by changed records or taxonomy revision.

## Original archive checks

- Swift 6.0.3 compiled the portable models, tag rules, search implementation, and tests on Linux.
- **11 XCTest tests passed, zero failures**: manual override preservation, invalid/duplicate names, rename/delete behavior, dangling assignments, combined tag/search matching, Unicode normalization, prepared-search caching semantics, Codable round trip.
- All application Swift sources passed Swift frontend syntax parsing. Parsing does not validate Apple framework types or API availability.
- Xcode project parsed successfully; source references, shared scheme, privacy manifest, and icon catalog were checked.
- App icon inspected as an opaque black PNG with white artwork.
- Source-level independent review checked the spec, data preservation, limited access, scan lifecycle, and UI simplification.

## Required Mac/iPhone verification

1. Production simulator compilation now passes with Xcode 27. Signing and an actual iPhone build/install remain to be completed.
2. Run on an Apple Intelligence-compatible iPhone. Allow full Photos access; confirm old and new screenshots, OCR, model-generated tags, and search results.
3. Repeat with limited and denied permissions; edit limited selection while the app is active and in Settings.
4. Try a screenshot stored only in iCloud with downloads off/on, and interrupted connectivity.
5. Pause/resume; background/foreground repeatedly; edit tags or delete screenshots during a scan. Confirm manual edits survive and saved data survives relaunch.
6. Rename/delete/create tags; combine search and filters; batch-assign/remove and rescan.
7. Confirm both deletion prompts and Photos Recently Deleted behavior using disposable screenshots.
8. Check light, black dark, Dynamic Type, VoiceOver, native search/toolbars, zoom, sharing, and rotation on-device.

Remaining product limits (bounded model excerpt, general visual labels, keyword search, foreground scanning, resized sharing, and local-only metadata) are explicitly documented in `README.md`.

## September 27 UI revision verification

- Icons precede names in filters, taxonomy management, and assignment controls. The searchable 64-symbol collection has named categories and semantic names shared with the local tagging prompt.
- Legacy tag records decode without `iconName`; old IDs and assignments survive. Unknown symbols fall back safely. Added four tests covering migration, fallback, rename/encoding preservation, and catalog invariants (15 core tests total, all pass).
- Native iOS 27 floating search minimizes to a circle, expands on tap, and combines with filters. A live count remains visible when the system hides the navigation bar during search; singular reads “1 screenshot.”
- Full-screen gallery pages through the current result set, follows thumbnail selection, retains query on dismissal, preloads only adjacent images, and follows the selected asset for actions. The existing zoom implementation is retained. Deletion of the current asset advances to a remaining neighbor by source inspection; actual Photos deletion remains a device gate.
- Two XCTest UI tests passed: circle-to-bar expansion, typed query/count, photo opening, thumbnail selection, swipe pagination, query retention; and icon search/selection, tag rename, reopen verification, cancelled creation, and filtering by the renamed tag.
- Every catalog symbol is asserted available using `UIImage(systemName:)` in the isolated fixture on iOS 27.
- Production build: `xcodebuild ... -sdk iphonesimulator ... CODE_SIGNING_ALLOWED=NO build` passed. Core suite: `swift test` passed. UI result: `/private/tmp/shots-ui-pass4.xcresult`.
- Native evidence is in `captures/redesign/`. The sample-library harness disconnects PhotoKit and index persistence; these tests do not establish actual photo permissions, OCR/model inference, iCloud, deletion, or relaunch persistence.
- No Git repository/remote was created and no release was uploaded. This checkout was recovered from an archive.

The checked-in reproduction script also passed both UI tests from a newly generated fixture: `/private/tmp/shots-redesign-repro/UITests.xcresult`.

## Grouping, hiding, and measured scanning revision

- Title uses native inline-large placement at the top left. Search keeps the header/count visible while its native field floats over the grid; the bottom toolbar background is hidden.
- Menu switches continuous/day-grouped layout; choice survives relaunch. Day groups use the local calendar, including DST boundaries. Tests cover ordering and local-day boundaries.
- App-local `hiddenAt` persists with each indexed screenshot, defaults to nil for old records, and leaves manual assignments intact. Hide/unhide works through viewer/thumbnail/selection controls, with a Hidden view for recovery. Hidden items are excluded from normal search and automatic scans; originals remain in Photos. This is not Photos' protected Hidden album.
- Scan stage timers use monotonic uptime. The progress bar reports attempted/total and active elapsed time, estimates remaining time after three samples, and retains completed counts through pause/resume. A changed taxonomy, modified image, iCloud policy, or AI availability starts a fresh timing scope so already-attempted work is not incorrectly skipped.
- Settings stores the last completed scan's count, failures, and load/Vision/local-AI durations. Durations contain no screenshot text or IDs.
- **Measured unthrottled run:** 15 synthetic 600×1000 screenshots in 62.75s (4.18s each); Vision 11.06s, Foundation Models 51.45s, sample-image loading/encoding 0.047s; zero failures, model available. This is simulator performance, not an iPhone benchmark, and bypasses PhotoKit/iCloud/index writes.
- `captures/library-update/benchmark.json` contains raw timings; `scripts/benchmark-simulator.sh` reproduces the clean run on the installed sample build. Normal UI previews bypass scanning. The dedicated six-image pause test runs real Vision/AI with a 700ms fixture load delay, so its screenshots are not the speed measurement.
- **Validation:** 18 core tests pass; grouping/hide/recovery, search/gallery, and icon editing passed in `/private/tmp/shots-v2-ui/UITests.xcresult`. Scan progress/pause/resume/final count passed in `/private/tmp/shots-v2-scan-final.xcresult`. An earlier scan assertion used a native label incorrectly, then a 15-image interaction run exceeded its 90s timeout; the final test uses an accessible count and six real samples with a longer bound. The clean speed benchmark still uses 15 images without delays or pauses.
- Physical iPhone performance, real PhotoKit/permissions/iCloud/deletion, saved-index relaunch behavior, and broad accessibility/rotation validation remain open. Synthetic scans demonstrate actual successful Vision and Foundation Models calls in this simulator.
