# Shotr project instructions

## Product and architecture

- Native iPhone app, SwiftUI with reusable UIKit collection views for the grid/viewer. iOS 26 minimum. No server, accounts, analytics, remote AI, or new external dependencies in the app. Shared UI comes from `../../packages/RDesign`.
- `Shots/Core/` is portable Swift and tested with `swift test`. `LibraryStore` owns the observable state, OCR-first scan pipeline, manual tag intent, persistence, and lifecycle. `Services/` wraps Photos, Vision, Foundation Models, and OS background continuation.
- Preserve version-1 index compatibility and manual tag additions/removals. Never replace successful OCR when automatic tagging fails.
- Treat 15,000 screenshots as a normal library. Reuse cells/pages, keep expensive preparation off the main actor, and avoid whole-library work per image or unrelated Photos notification.
- Sticky date headers must remain opaque during date handoff, including short/partial rows. Scanning must not report user pause during refresh or task handover; preserve genuine pause/cancellation behavior.
- Background text indexing is opt-in, per-session, OS-controlled, and CPU-only. AI enrichment and Photos discovery remain foreground-only. Do not promise always-on processing.

## Working and verification

- Preserve unrelated changes. Use subagents for independent changes with disjoint file ownership when useful; integrate and verify their work.
- Run `just test` for core/release-tool changes. Run `just verify` for app changes before release: native UI uses an isolated generated fixture, never personal Photos.
- Every new production Swift file must also be included in `Shots.xcodeproj/project.pbxproj`; the Swift package is not the iOS app build.
- Add executable regression tests. Source-text checks are not behavioral evidence. Header transitions need actual geometry/pixel evidence; unchanged Photos refreshes must not interrupt active work.
- Simulator fixtures/performance are not proof of physical-device Photos, iCloud, AI, or actual OS background runtime. State those remaining limitations honestly.
- Keep `README.md`, `REVIEW.md`, and `HANDOFF.md` current when behavior or release evidence changes. Old release notes are historical, not current task state.

## Release and Git

- This app lives in `apps/shotr` in Calum's apps monorepo. Preserve `com.calum.shots`, the `Shots` scheme/module, and on-disk index paths; display/product name is Shotr.
- Shared release entrypoint from the repository root: `bundle exec fastlane ios beta app:shotr`. `app.yml` disables automatic TestFlight delivery until monorepo native/signing checks pass. Follow `../../docs/RELEASE.md`; never infer upload authorization from a Git push.
- `just verify` is the app-specific full native gate. `just release-status BUILD` retains read-back for historical releases. The legacy `scripts/release.py` uploader remains for recovery only; the shared Fastfile owns normal distribution.
- Build numbers are selected above local/App Store Connect builds and applied as an archive override; never upload a previously used build number, overwrite preserved artifacts, or retry an uncertain upload blindly. Use `just release-status BUILD` to verify instead.
- Legacy recovery credentials come from environment variables or an explicitly configured `SHOTS_SECRETS_WRAPPER`; the shared Fastfile uses the root release configuration. Never print keys/tokens, commit private signing assets, or put secret values in command arguments. Temporary upload keys must be mode 0600 and cleaned.
- `.release/`, archives, IPAs, signing keys, provision profiles, and local build outputs are ignored. `release/ExportOptions.plist` is non-secret configuration; keep existing signing identity/profile unless explicitly asked to change them.
- Ask before destructive actions and externally visible changes not already requested. Never bypass denied tools with another route.
