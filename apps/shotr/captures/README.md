Current captures: **[iOS 27 supported-runtime screenshots](ios27/README.md)**. The notes below describe the earlier compatibility previews.

# Shots native UI captures — September 27, 2026

These PNGs are unedited simulator framebuffer captures of running SwiftUI screens.

- Device: iPhone 16 Pro simulator, iOS 18.3.1.
- Captures: light library, black dark library, search for `weekend` (four results), tag manager.
- Content: 15 synthetic screenshot fixtures, manually assigned sample tags. No personal photo library was used.
- This is an isolated compatibility capture build, not production acceptance: PhotoKit and Foundation Models are replaced in the temporary capture copy, deployment is lowered to iOS 18, and initial search/sheet states are selected through launch arguments.
- Production app sources are unchanged from the recovered ZIP. The original iOS 26+ project builds successfully with the Xcode 27 simulator SDK, and all 11 portable core tests pass on this Mac.
- Real Photos permission/import, OCR, automatic tagging, persistence, sharing, deletion, and iOS 26+ runtime appearance still need verification.

The reproducible capture-copy generator is `scripts/make-capture-project.py`. It creates `/private/tmp/shots-capture-source` and refuses to overwrite an existing copy.

Build logs: `/private/tmp/shots-build.log` (original app), `/private/tmp/shots-capture-build.log` (capture harness).

A compatible iOS 27 runtime download was started with `xcodebuild -downloadPlatform iOS -exportPath /private/tmp/shots-runtime`; progress is in `/private/tmp/shots-runtime.log`. At capture delivery it was still downloading, not installed.
