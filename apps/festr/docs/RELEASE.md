> Historical release notes from before the monorepo. Current commands and paths: [root release guide](../../../docs/RELEASE.md).

# Releasing Festr

Festr uses the same release setup as Tendr: XcodeGen `project.yml` with the generated `Festr.xcodeproj` checked in, fastlane lanes in `fastlane/Fastfile`, and GitHub Actions on macOS 15 with Xcode 26.2.

## Automatic TestFlight releases

[TestFlight workflow](../.github/workflows/testflight.yml) runs on every push to `main`. With all secrets present it imports the distribution certificate into a temporary keychain, then runs `bundle exec fastlane ios beta`:

1. `swift test` (core unit tests).
2. `ensure_app_record`: registers the `com.calumwebb.festr` and `com.calumwebb.festr.widgets` bundle IDs if needed, checks the App Store Connect app record exists, and creates the internal **Owner Preview** TestFlight group if missing.
3. Next build number = `latest_testflight_build_number + 1`.
4. On CI, `sigh` fetches or creates one App Store profile per target (**Festr CI App Store**, **Festr Widgets CI App Store**) for the installed certificate, and `update_code_signing_settings` switches each target to manual signing with its profile.
5. Archive, export, upload, wait for processing and assign the build to **Owner Preview**.

Without the secrets the workflow still runs core tests and an unsigned Release build, then stops before signing and upload, listing the missing secrets in the job summary.

## Required repository secrets

`0x63616c` is a personal account, so there are no organization-level secrets; GitHub Actions secrets have to be added to this repository (**Settings → Secrets and variables → Actions**, or `gh secret set NAME -R 0x63616c/festr`). Tendr uses the same names, so the values from Tendr's release Mac (`.env.tendr` and the exported `.p12`) can be reused as-is.

| Secret | Value / format |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API key ID. |
| `ASC_ISSUER_ID` | Issuer ID for that key. |
| `ASC_KEY_CONTENT` | Raw `.p8` contents including the PEM header/footer (not base64). Use an **App Manager** (or Admin) team key so it can manage profiles, upload and manage TestFlight groups. |
| `ASC_BETA_FEEDBACK_EMAIL` | Email that receives TestFlight feedback. |
| `BUILD_CERTIFICATE_BASE64` | Base64 of an exported **Apple Distribution** `.p12` (with private key) for team `X9E4HG27NK` (`base64 -i release.p12 \| pbcopy`). |
| `P12_PASSWORD` | Password of that `.p12`. |

Optional, for the App Store release workflow only: `ASC_REVIEW_PHONE`, `ASC_REVIEW_EMAIL`.

Example (from the release Mac):

```bash
set -a; source .env.tendr; set +a
for name in ASC_KEY_ID ASC_ISSUER_ID ASC_BETA_FEEDBACK_EMAIL; do gh secret set "$name" -R 0x63616c/festr --body "${!name}"; done
gh secret set ASC_KEY_CONTENT -R 0x63616c/festr < "$ASC_KEY_PATH"
base64 -i release.p12 | gh secret set BUILD_CERTIFICATE_BASE64 -R 0x63616c/festr
gh secret set P12_PASSWORD -R 0x63616c/festr
```

## App Store Connect app record

The App Store Connect API cannot create apps, so the record needs one of:

- App Store Connect → Apps → **New App**: iOS, name **Festr** (fallback **Festr: Festival Set Times** if taken), primary language English (U.S.), bundle ID `com.calumwebb.festr`, SKU `festr`. The bundle ID appears once `ensure_app_record` (or the `create_app` lane) has registered it.
- Or locally with an Apple ID session: `bundle exec fastlane ios create_app` (uses `produce`, tries both names, and registers the widget bundle ID).

Live Activities need no extra capability or entitlement.

## Verification and recovery

`ruby scripts/check-release.rb` exercises the real Fastfile with stubbed actions: local vs CI signing, per-target profiles, the app record gate, build numbering, distribution and failure gates, plus listing limits. The [CI workflow](../.github/workflows/ci.yml) runs it with `swift test`, an unsigned device build, the UI flow tests and the screenshot capture.

If a run times out after upload, check App Store Connect first; `bundle exec fastlane ios distribute_existing build:N` assigns an already processed build without rebuilding.

## App Store review preparation

[App Store release workflow](../.github/workflows/release.yml) (manual, or an `app-store/*` tag) captures screenshots with `scripts/capture-screenshots.sh`, uploads `fastlane/metadata` and the screenshots with `deliver`, selects the latest processed build and answers the age rating. It never submits for review. The privacy and support URLs point to `site/` on GitHub Pages (`https://0x63616c.github.io/festr/`); enable Pages for the repository (it is private, so this needs a plan that allows Pages on private repositories, or host `site/` elsewhere and update the URL files).
