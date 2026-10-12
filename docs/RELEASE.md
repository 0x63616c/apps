# Releases

All release commands run at the repository root, with `bundle install` first. The root `fastlane/Fastfile` reads `apps/<app>/app.yml`: project, scheme, unchanged bundle ID, profile name, version, TestFlight flag/group and consumable tips. Festr also lists the widget’s separate signing profile under `signed_targets`.

```sh
ruby scripts/check-release.rb             # no Apple access
bundle exec fastlane ios verify app:tendr
bundle exec fastlane ios beta app:tendr
bundle exec fastlane ios distribute_existing app:tendr build:18
bundle exec fastlane ios prepare_review app:tendr
```

`beta` tests, selects the next build number, archives, uploads, waits for processing and distributes to the configured internal group. Concurrent publishers for one app can race; do not run a local upload alongside its Actions job. Automatic main-branch delivery is enabled for Tendr. Shotr and Festr start with `testflight: false`; verify their App Store records, profiles and internal groups before enabling them. The flag controls automatic and manually dispatched Actions delivery; an explicit local `beta app:...` command remains available.

`.github/workflows/testflight.yml` detects affected binaries with `scripts/changed-apps.sh --build --only testflight`. App code and shared design/release changes trigger enabled apps. Docs, listing copy, site and web changes do not. Manual dispatch also requires `confirm_branch_release` for a non-main branch. Every execution job has a timeout; macOS jobs respect `MACOS_RUNNER` and `DEVELOPER_DIR` (see root README).

Actions requires `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`, `ASC_BETA_FEEDBACK_EMAIL`, `BUILD_CERTIFICATE_BASE64` (Apple Distribution certificate and private key exported as P12), and `P12_PASSWORD`. Store them as GitHub secrets. The workflow imports a temporary keychain; `sigh` creates/reuses the configured profiles. Festr archives use target-specific profiles for both the app and widget. Temporary signing edits are restored, and the workflow removes its profiles/keychain afterward. Never commit secrets or signing files.

Locally, provide the ASC variables above and either `ASC_KEY_PATH` or `ASC_KEY_CONTENT`. Xcode automatic signing is preserved outside Actions. For a single-target app, `R_PROFILE_UUID` opts into manual local signing. Festr uses local Xcode signing; its target-specific CI profiles are configured automatically only in Actions.

The manual Release workflow accepts an app slug and calls `prepare_review`: uploads app-local metadata/screenshots, sets free pricing where needed and attaches a processed build. It stops before Submit for Review. Optional `ASC_REVIEW_PHONE` and `ASC_REVIEW_EMAIL` supply review contact details. Tendr has the shared capture/frame configuration; Shotr and Festr retain their app-local screenshot tools and should use `skip_screenshots` until their shared capture configuration is added. Their metadata remains app-local.

```sh
scripts/capture-screenshots.sh tendr
scripts/frame-screenshots.sh tendr
bundle exec fastlane ios metadata app:tendr
bundle exec fastlane ios review_status app:tendr
```

Tendr’s optional tips are configured in `apps/tendr/app.yml`, `Tendr.storekit`, and `Still/Features/Journal/Tips.swift`. Keep product IDs aligned. `tip_iaps app:tendr` updates consumable records and review screenshots without submitting. RDesign’s `RTipJar` unlocks no features.

After an uncertain upload, check App Store Connect before retrying. Confirm processing, the correct internal group and tester availability. For an already processed build use `distribute_existing`, which uploads no new binary. Native builds, Apple signing, App Store Connect calls and live Actions execution cannot be validated by Linux tests.

Historical Tendr release evidence remains in [apps/tendr/docs/RELEASE.md](../apps/tendr/docs/RELEASE.md); its old root paths are historical. App-local legacy release scripts are retained only for recovery, not automatic delivery. The root lane is the current release authority.
