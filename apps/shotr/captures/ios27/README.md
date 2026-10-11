# Supported-runtime captures

Captured September 27, 2026 from a running iPhone 16 Pro simulator on iOS 27.0 (24A434). All four images were visually inspected after capture.

- light.png: light library with synthetic screenshot images.
- dark.png: the same library with a black app canvas.
- search.png: native search for `weekend`, displaying four matching sample records.
- tags.png: the native tag manager showing all ten default tags.

These are unedited simulator framebuffer captures, not mockups. The capture build retains the original Xcode project, minimum iOS 26 target, Foundation Models implementation, and UI layouts. It substitutes an in-memory sample library for Photos and persistence, and adds launch arguments to open search/tag screens. Automatic AI tagging is not exercised.

Original application: successful Xcode simulator build, 11 passing portable core tests. Those checks do not prove real Photos, OCR, AI inference, persistence, deletion, sharing, or physical-device behavior.

Reproduce the isolated source copy with `python3 scripts/make-capture-project.py --destination /private/tmp/shots-supported-source` from the repository directory, using a fresh destination. Build the generated Xcode project for iOS Simulator, install it on a supported simulator, then run `bash scripts/capture-simulator.sh SIMULATOR_UDID OUTPUT_DIRECTORY`.

See evidence.json for runtime identity, app deployment target, image dimensions and SHA-256 hashes. The earlier captures one directory above are explicitly labeled iOS 18 compatibility previews; these are the current supported-runtime captures.
