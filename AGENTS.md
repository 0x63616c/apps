# Project agent memory

- Start with [README.md](README.md). Xcode configuration is owned by `project.yml`; regenerate and commit `Festr.xcodeproj` after changing it (`xcodegen generate`; XcodeGen also builds and runs on Linux).
- Core logic lives in `Festr/Core` (pure Foundation, compiled into the app, the widget extension and the `FestrCore` Swift package). `swift test` is the fast gate and also runs on Linux. UI code needs the macOS CI runner (Xcode 26.2, iOS 26 SDK).
- Times are always shown in the festival's IANA time zone via `FestivalClock`; never format set times with the device time zone.
- Never invent set times. Bundled data comes from `data/festivals.source.json` via `scripts/make-seed-feed.py` (CI checks the generated file is current). Artist names are plain text; no festival logos or "official" wording.
- Release: [docs/RELEASE.md](docs/RELEASE.md). `ruby scripts/check-release.rb` verifies the lanes without Apple credentials. The `--screenshots` launch argument pins the clock to Saturday 8:05 PM at Head Trip; `--now <ISO-8601>` pins it for UI tests.
- Uploading an IPA does not prove TestFlight processing or group availability; check App Store Connect.
