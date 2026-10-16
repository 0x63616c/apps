# Calum’s apps

Native iPhone apps, shared design, and their websites. This repository is still named `tendr`; the planned rename to `apps` is documented in [docs/RENAME.md](docs/RENAME.md).

| App | Source | Bundle ID | Core tests |
| --- | --- | --- | --- |
| Tendr | [apps/tendr](apps/tendr) | `com.calumwebb.still` | `swift test --package-path apps/tendr` |
| Shotr | [apps/shotr](apps/shotr) | `com.calum.shots` | `swift test --package-path apps/shotr` |
| Festr | [apps/festr](apps/festr) | `com.calumwebb.festr` | `swift test --package-path apps/festr` |

[packages/RDesign](packages/RDesign) provides the black, white and graphite palette, type, spacing, cards, rows, info popovers, settings links, splash and optional StoreKit tip jar. Its `rframe` executable renders App Store screenshot frames on macOS. `swift test --package-path packages/RDesign` also runs its portable tests on Linux.

[web/festr-admin](web/festr-admin) is the festival editor. From that directory run `bun install --frozen-lockfile`, `bun run build`, `bun run lint`, and `bun run test`. Database commands need its documented local environment; the build does not. Its seed script reads the bundled feed in `apps/festr`.

Native builds require macOS and Xcode 26.2 or later. Tendr and Festr use XcodeGen 2.44.1: run `xcodegen generate` inside the app directory after changing `project.yml`. Shotr’s checked-in project is maintained directly. Open the app’s `.xcodeproj`; schemes remain `Still`, `Shotr`, and `Festr` respectively. Simulator builds use `CODE_SIGNING_ALLOWED=NO`.

Shared release commands run from the repository root with `app:<slug>`; see [docs/RELEASE.md](docs/RELEASE.md). CI selects changed apps using `scripts/changed-apps.sh`. `MACOS_RUNNER` may be a runner label or a JSON label array; the default is `macos-latest`. `DEVELOPER_DIR` defaults to `/Applications/Xcode_26.2.app/Contents/Developer`. Override it when the selected runner installs a newer supported Xcode elsewhere.

```sh
ruby scripts/check-release.rb
python3 scripts/test-changed-apps.py
shellcheck scripts/*.sh apps/*/scripts/*.sh
actionlint
scripts/new-app.sh Samplr samplr
```

[scripts/new-app.sh](scripts/new-app.sh) creates a native app and Pages skeleton from [templates/new-app](templates/new-app). [docs/IMPORT.md](docs/IMPORT.md) describes history-preserving imports. [site/README.md](site/README.md) covers Pages previews and publication.

Keep changes focused. Use synthetic screenshot fixtures. Never commit signing assets, credentials, or personal health data. Core or Linux checks do not prove native UI correctness, signing, or TestFlight availability. See [AGENTS.md](AGENTS.md) for working rules and [docs/VERIFICATION.md](docs/VERIFICATION.md) for migration evidence.
