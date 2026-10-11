# Shots current handoff

Recovered September 26–27, 2026 from Shots(1).zip attached to the ChatGPT conversation “Screenshot organizer apps.” GitHub returned repository-not-found for 0x63616c/shots; no remote was created or pushed. This directory is recovered source, not a Git clone.

## Current revision

Implemented the original UI redesign plus the user's latest request: top-left Shots title, native floating search preserving the header, persistent Continuous grid / Grouped by day menu choice, reversible app-local hiding, and timed scanning with a progress bar, elapsed/estimated remaining time, pause/resume, and Settings timing history.

- `Models.swift`: tag icon catalog, backwards-compatible optional `hiddenAt`, calendar day groups, scan measurement/estimate model.
- `LibraryStore.swift`: hidden filtering/persistence, monotonic stage timing, pause/resume counters, fresh timing scope on changed scan inputs.
- `LibraryView.swift`: native inline-large title, layout picker, hidden recovery view/actions, scan progress.
- `ScreenshotDetailView.swift`: full-screen paging/filmstrip, hide/unhide and existing zoom/share/delete/tag controls.
- `SettingsView.swift`: last scan time/count/failure and stage breakdown.

## Verified

18 core tests pass. Four native UI flows pass across the suite and focused scan rerun: search/gallery, icons, grouping/hide/unhide/layout relaunch, and scan pause/resume/final count. Production simulator builds with Xcode 27. Current images are `captures/library-update/`; previous revisions remain separately labeled.

Clean benchmark: 15 generated 600×1000 images in 62.75s, Vision 11.06s and local AI 51.45s, zero failures. Foundation Models was available and performed actual inference in the simulator. This bypasses real Photos/iCloud/index writes and does not establish iPhone speed. Raw data: `captures/library-update/benchmark.json`.

Reproduce UI: `bash scripts/run-ui-tests.sh SIMULATOR_UDID NEW_OUTPUT_DIRECTORY` (XcodeGen required). Reproduce timing after fixture install: `bash scripts/benchmark-simulator.sh SIMULATOR_UDID OUTPUT_JSON`. The pause/resume test uses six samples and a deliberate fetch delay; the benchmark uses 15 without delay. Never quote the delayed UI test as performance.

Simulator: Shots iOS 27, iPhone 16 Pro, UDID `5C5A6D35-1FD0-4FB6-864C-B4C819AE2ADB`, iOS 27.0 (24A434). Initial UI result `/private/tmp/shots-v2-ui/UITests.xcresult`; final scan test `/private/tmp/shots-v2-scan-final.xcresult`. See REVIEW.md for exact test scope and earlier assertion/timeout fixes.

## Remaining project gates

Run the production app with disposable screenshot assets to validate Photos/OCR/search/tagging lifecycle and actual persistence. Simulator Foundation Models inference now works; physical-device inference/performance still needs verification. Verify permissions/iCloud, deletion, zoom, accessibility/large text, and rotation on-device. Distribution signing and IPA export are verified; TestFlight upload/distribution and GitHub upload remain unfinished. Do not call the overall project finished merely because UI previews exist.

Notification preference for this chat: send honest milestones/completion to https://ntfy.sh/0x63616c. This preference was scoped to this chat.


## TestFlight release — September 27, 2026

The active goal is an installable internal TestFlight build for Calum. Production archive and export succeeded for **1.0 (1)**, bundle `com.calum.shots`, team `X9E4HG27NK`, minimum iOS 26. Exported IPA signature is valid; non-exempt encryption is false. The privacy manifest declares UserDefaults CA92.1 and SystemBootTime 35F9.1 (scan elapsed measurement). No sample-fixture binary was archived.

- Archive: `/private/tmp/shots-release/Shots.xcarchive`
- IPA: `/private/tmp/shots-release/export/Shots.ipa` (739621 bytes)
- IPA SHA256: `a7dc3ed9a340de164ef6bc0871faa94e5341ff91816f002b9f4e5a080ebf3e50`
- Export options: `release/ExportOptions.plist`
- Bundle ID resource: `PCY4HXGULV`
- Active App Store profile: `ZQ8Y26R645`, “Shots App Store”, UUID `3876e705-5e62-474c-8da4-e0ebc1182bdd`
- Existing Apple Distribution certificate: `FJ2QSP6YH8`, expires April 12, 2027. No new certificate created or old certificate revoked.

Existing App Store Connect API credentials work through the sibling world-wide-webb project's `scripts/secrets.sh` wrapper (encrypted vault / Keychain; do not print secrets). A new app listing is still required. The saved Apple web session expired; Chrome is on App Store Connect sign-in, and the user has been asked to sign in. 1Password CLI item access timed out waiting for authorization. Do not repeat broad credential searches or claim an upload has occurred.

Temporary helpers `/private/tmp/shots-asc.py` (JWT API reads), `/private/tmp/shots-upload.py` (protected temporary key, altool upload) are ready. The uploader checks that the listing exists. After sign-in: create the iOS Shots listing with bundle `com.calum.shots`, SKU `com.calum.shots`, primary language English (US); upload the production IPA; verify processing succeeds, assign the account holder to an internal beta group, and read back build availability. Only then report TestFlight completion.

## TestFlight retry — October 3, 2026

The user requested end-to-end TestFlight setup and does not want to perform listing/setup steps; they only want to install after receiving an invitation. No active OpenCode goal exists in this session. No invitation has been sent and no upload has occurred.

- The old temporary export and helper scripts are gone; the old archive contains no app. Rebuilt and exported the current production sources successfully using the existing Apple Distribution identity and “Shots App Store” profile. No certificates/profiles were created or revoked.
- Production version **1.0 (1)**, bundle `com.calum.shots`, minimum iOS 26. Non-exempt encryption is false; archive signature verification passed. Production binary has no sample-fixture markers. All 18 core tests passed; physical-device behavior is still unverified.
- Preserved IPA: `release/testflight-20261003/Shots.ipa` (739744 bytes; excluded from Git).
- SHA256: `d9b53a6932d8cdadb986f2dcdcdd5ee092a5df325e5ce6fd95a5b40a9663d46c`.
- Archive/export/DerivedData: `/private/var/folders/1d/vw9hk87s6h1b1d3z_mh2mj7c0000gn/T/opencode/shots-testflight-20261003/`.
- App Store Connect API credentials still work via the sibling project's protected `scripts/secrets.sh` wrapper. Two API reads confirmed no app listing for `com.calum.shots`; bundle resource `PCY4HXGULV` exists.
- Listing creation via fastlane/API was explicitly rejected by Apple: `The resource 'apps' does not allow 'CREATE'. Allowed operations are: GET_COLLECTION, GET_INSTANCE, UPDATE`. Both cached and vault-provided Apple web sessions are expired. No interactive login was attempted. Browser/computer-control tools are not available in this session.
- Concrete blocker: creating the initial app listing requires an authenticated Apple web session/browser connection. Once that access is available, create the listing, upload the preserved production IPA, verify processing and internal tester assignment/availability, and send the invitation. Do not report TestFlight completion before read-back verification.

### Browser access and listing created — October 3 follow-up

The user explicitly authorized using their Chrome and enabled Chrome remote debugging. Configured global OpenCode MCP `chrome-devtools` with `chrome-devtools-mcp --autoConnect --no-usage-statistics --no-performance-crux`; reloaded the current location. Connection succeeded, using the user's existing Apple web sign-in in a newly created tab. Their other tabs were not changed.

- Apple rejected the listing name “Shots” as already used. Created **“Shots: Screenshot Organizer”**, keeping bundle `com.calum.shots`, SKU `com.calum.shots`, English (US), iOS, full access. App ID **6818884320**; creation verified through the public API. On-device display name remains Shots.
- Created internal group **Calum**, ID `a72d0ddb-1a61-41d5-b660-b99e7cd45391`, with automatic distribution enabled. Added the existing account holder `calumpeterwebb@icloud.com`; API read-back confirmed internal group, access to all builds, and exactly one assigned tester (`bd9581ba-7a5d-42aa-983a-032b7c27e059`). At this checkpoint its state is `NOT_INVITED` because no build is available yet.
- Added English beta app description and feedback email through the public API.
- Production IPA upload launched through `shots-upload.py` in the approved OpenCode temporary directory. It uses an ephemeral mode-0600 P8 file, cleaned automatically, and `altool --upload-package --wait`. Background shell ID `sh_103c24d49001JOSuGz2HyVvxmJ`; wait for its completion notification, do not poll or upload a duplicate while it runs. Processing and invitation remain unverified at this checkpoint.
- User asked about making many apps easier. Clarified: public API does not create initial app listings, but fastlane produce/private web endpoints can with an authenticated Apple web session; signing, uploads, and tester distribution can be automated. No general multi-app bootstrap tool has been requested or implemented yet.

### TestFlight complete — October 3, 2026

Production **1.0 (1)** uploaded successfully with no errors. Apple processing completed with `VALID`; build/delivery ID `221cb980-d339-4886-8e35-2f6531f22ab2`. API read-back confirmed:

- The Calum internal group includes this processed build and exactly one tester, `calumpeterwebb@icloud.com`.
- Tester state is **INVITED**, invite type EMAIL.
- Build beta detail: **IN_BETA_TESTING** for internal testers, `autoNotifyEnabled: true`. External state remains `READY_FOR_BETA_SUBMISSION`; no external beta review or public App Store submission was performed.
- Build expires January 1, 2027; minimum iOS 26. This proves TestFlight distribution/invitation, not physical installation or on-device functional validation.

The user can accept Apple's email invitation to **Shots: Screenshot Organizer** and install through TestFlight. Future uploads inherit automatic distribution to the Calum internal group. Use a new build number for a new upload; do not upload version 1.0 build 1 again.

## Large-library fixes and build 2 — October 3, 2026

User requested fixes for a laggy 15,000-screenshot library, slow categorization, sticky date headers, background scanning, centred viewer selection, separate Share/Tags buttons, and numeric-only counts. Four subagents handled the pipeline, viewer, background coordinator, and regressions; parent integrated and audited the result.

- Reusable UICollectionView grid/pager; pinned opaque day headers; constant-time viewer ID/index lookup; centred fixed-width filmstrip including edges; separate toolbar glass buttons; count-only header. Cold search normalization, Photos enumeration, resizing, and JPEG encoding run off the UI actor.
- OCR-first checkpointed indexing before single-request AI enrichment. Incremental search/day caches; full-index checkpoints after 100 operations or 30 seconds at operation boundaries and on phase/exit. Manual tag intent and version-1 index schema remain compatible.
- Settings has per-session **Continue scan in background**, using a real registered BGContinuedProcessingTask, CPU-only Vision, system progress/cancellation, and foreground-only AI/discovery. iOS admission/duration and physical-device behavior remain unverified. Do not claim always-on background operation or measured speed on the user's phone.
- Final independent evidence: 23 core tests pass; all 8 native UI flows pass in approved temp `shots-native-ui-20261003-ready-4/UITests.xcresult`, including 15,000-image edge paging/centering and sticky headers. Native evidence preserved in `captures/performance-update/`. Earlier three-column sizing regression was found and fixed; final full suite is clean.
- Project build number is now **2**. Signed production archive/export succeeded using existing signing assets. Archive/export/DerivedData: approved temp `shots-performance-release-20261003/`. Preserved IPA: `release/testflight-20261003-build2/Shots.ipa` (871162 bytes), SHA256 `d1a074036bd542ecc9162ee0c0c4eb866ad518dc722d7dcf0e04641f0c9da1e6`. Signature and production plist/fixture exclusion checked.
- User explicitly said **ship it to TestFlight**. Build 2 upload is running via the protected secrets wrapper and new approved-temp `shots-upload-build2.py`, which checks the signed artifact hash/version, app ID, and duplicate builds before upload. Background shell `sh_104795e410012z9ttRRUpj31D6`; wait for its completion notification, do not poll or upload another copy. Build processing/group availability is not yet verified. The helper keeps the P8 key in a mode-0600 ephemeral file, cleaned automatically.
- Active OpenCode goal: **Ship to TestFlight.** Close only after read-back confirms build 2 is processed and available to the existing Calum internal group. No external/public App Store submission is requested.
- `no-mistakes axi` cannot run in this non-Git recovered checkout. No Git/PR/CI pass was claimed; independent tests, review, compilation, and signing checks are the release evidence.

### Build 2 shipped — verified

Apple upload succeeded with no errors and processing returned `VALID`. Delivery/build ID **a141671b-5c55-43be-a69c-08ef08dced28**. Protected API read-back confirmed build **2**, `VALID`, internal state **IN_BETA_TESTING**, automatic notifications enabled, membership in the **Calum** internal group, and the existing tester present. Expires January 1, 2027; minimum iOS 26. External state remains `READY_FOR_BETA_SUBMISSION`; no external/public submission was performed. The user can update through their existing TestFlight app.

Distribution verification helper: approved-temp `shots-testflight-build2.py`; sanitized result `shots-build2-distribution.json`. The upload is complete; **do not upload build 2 again**. Future production uploads need build number 3 or higher. The signed artifact and tester availability are verified, not physical installation or real-library/background runtime.

Final simulator benchmark with actual local AI: 15 synthetic images, 36.39s wall time, zero failures, compared with historical 62.75s (~42% less wall time). Preserved in `captures/performance-update/benchmark.json`. This bypasses PhotoKit/iCloud/index writes and is not an iPhone guarantee. Stage latency totals include queue waiting/overlap and need not add up to elapsed wall time.

## October 4 follow-up — local release and source repository

User reported repeated “paused” flashes during scanning and screenshot pixels above incoming pinned date headers. Source fixes filter unrelated Photos changes, discover relevant changes before cancelling scan work, reject stale refresh snapshots, expose real pause reasons, and use an adjacent custom grid/header layout with a one-physical-pixel opaque edge bleed. New regression fixtures exercise the real refresh path with notifications every 500ms and sample actual screenshot pixels at fractional date handoffs in both directions. Integration validation is in progress; these follow-up changes are **not yet uploaded to TestFlight**.

User then explicitly requested a remote repository, `AGENTS.md`, a local one-command release, and a push; **no CI yet**. Created private **https://github.com/0x63616c/shots** and initialized `main` with that `origin`. `just test`, `just verify`, `just release`, and `just release-status BUILD` are the local interfaces. The release command uses clean Git revisions, runs core/tool/native tests and unsigned Release compilation, allocates a new build number, signs/exports/audits the production IPA, uploads exactly once, and reads back internal group/tester availability. No upload is performed on push or on `just verify`.

Protected credential wrapper defaults to the sibling `world-wide-webb/scripts/secrets.sh`, overridable with `SHOTS_SECRETS_WRAPPER`. Signing assets stay in Keychain. Existing IPA/archive/fixture outputs and all credential/signing files are ignored, not committed. `just release-status 2` successfully read back the existing `VALID`/`IN_BETA_TESTING` build and group/tester availability. Release protocol unit tests use fake API/uploader interfaces, not real publishing.

### Follow-up validation complete

Final **`just verify` passed**: 28 Swift core tests, 15 release protocol tests, all 10 native UI flows, and unsigned production Release build. Native result: `.release/verify-rzhmq1no/ui/UITests.xcresult`, summary `Passed`, 10 passed / 0 failed / 0 skipped. Header pixels pass 320 controlled forward/reverse samples across four date boundaries in both orientations/appearances. Refresh notifications every 500ms do not interrupt progress or show pause; genuine Pause/Resume still passes. Screenshots and sanitized evidence: `captures/followup-20261004/`.

Independent release-tool review found and rechecked fixes for inherited secret-vault exposure, uncertain upload results permitting another upload, and remote-number races. Executable tests cover successful orchestration, validation/source/race failures, temporary key permissions/cleanup, unresolved-upload blocking/read-back recovery, and verify-only dispatch. Actual build-2 status read-back works; no new TestFlight upload was performed. The latest publication authorization is for the **GitHub push**, not an extra beta upload. Use `just release` when the user requests the next TestFlight release.

### Build 3 shipped — user subsequently approved release

The preceding validation/upload-pending notes describe the earlier stage only. User then explicitly said **“oh shit go do that right now”** in response to the fixes not yet being in TestFlight. Ran **`just release`**, not an ad-hoc upload: 28 core + 15 release-tool + 10 native UI tests passed again, unsigned Release compilation passed, clean source revision `dc4ab851adc5b3a93f565ce8b675f63d9ac20e3c` archived/exported and signatures/plist/fixture exclusions verified. No source changes occurred during validation/signing.

**Shots 1.0 (3)** uploaded successfully, delivery/build ID `959ccc48-97c9-46cf-8f60-23f7e434cf28`. Release and independent `just release-status 3` read-back both confirm `VALID`, `IN_BETA_TESTING`, Calum internal group membership, existing tester present, auto-notify enabled, and `ready: true`. Both reported regressions are now in TestFlight. No external/public submission or phone installation was performed.

Preserved IPA: `release/testflight-20261004-build3/export/Shots.ipa`, 941044 bytes; SHA256 `7c1d8341729e2235dfb852fc9c052df9ec178d1ff1a4934f25ff80d9fe11d69a`. Receipt: the release directory's `release.json` (`uploadResolved: true`); fresh native tests: `ui/UITests.xcresult`. Local archives/IPA/results remain ignored, not pushed. **Do not upload build 3 again.** `just release` selects 4 or higher next time; project build number remains 2 intentionally, because releases use an archive-only override. The full local release command is now verified with a real production upload, not only mocked orchestration tests.


## October 6 — description-first categories and favorites shipped

Shots **1.0 (4)** is available in the existing Calum internal TestFlight group. Apple processing is `VALID`, internal state `IN_BETA_TESTING`, tester present and automatic notifications enabled. Build ID `3e8979de-47b2-4f4e-a6dc-9a117f94d27c`. Independent `just release-status 4` also confirmed `ready: true`. Released source `6a7ea2c7bfdf97ad938c8963e99f07322e06ca05` pushed to origin/main. `just release` passed 46 core + 15 tool + 12 native tests, unsigned Release compilation, signed archive/export and device artifact audits. The native run used isolated synthetic Photos, including all 320 header transitions. Physical-device image inference remains unverified; text-model limitations are recorded in REVIEW.md.

Description-first category discovery, persisted searchable descriptions, viewer **••• → Analysis details**, heart and Favorites filter are included. Manual taxonomy/tag intent, dismissed categories, version-1 indexes and favorites survive AI changes. Image refusal gets a bounded text fallback; explicit Rescan retries the image. Discovery retries reduced samples within seven requests.

Receipt: `release/testflight-20261006-build4/release.json`, resolved upload. IPA: `export/Shots.ipa`, SHA256 `1f7e93a99e9eb7643cdd7c4da075badfa02011c1ffcd0c1e6b95c277f32c87d8`. **Do not upload build 4 again**; next release selects a fresh number. No external/public release or phone installation performed.

User explicitly instructed **no-mistakes only when asked**. Its pipeline was cancelled and configuration/remote removed. Continue normal direct review, tests and authorized shipping; do not invoke that pipeline automatically.
