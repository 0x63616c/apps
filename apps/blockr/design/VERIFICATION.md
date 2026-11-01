# Design verification — APP-13

Design artifacts only. Renamed `apps/blocker` to `apps/blockr` with `git mv`. No app code, Xcode project, entitlement, app manifest, shared component or production website changed. App Store product wording deliberately retains “App Blocker” in **Blockr: App Blocker**.

## Artifact checks

| Exact command / inspection | Exit / result |
| --- | --- |
| `python3 apps/blockr/design/build.py` | **0**; generated 118 standalone HTML fixtures, per-platform inventory and labelled contact sheet in flow order. Removes obsolete HTML/PNG fixtures. |
| `PLAYWRIGHT_MODULE=/tmp/wk2/node_modules/playwright node apps/blockr/design/render.mjs` | **0**; re-rendered all 118 screen PNGs and the full contact sheet with external Playwright and `/usr/bin/google-chrome`. No app dependency added. |
| `python3 apps/blockr/design/verify.py` | **0**; validates inventory parity, local HTML/image links, PNG signatures/dimensions, product naming, absence of small-print notes, one action per shield, ascending presets/custom chips and exactly one selected duration per state. Checks renderer findings as well. |
| [render-report.json](render-report.json) | 118 findings; zero browser/resource errors, zero content-overflow findings, zero out-of-frame findings. |
| PNG dimensions | iPhone 804 × 1748; Mac window/browser 2240 × 1520; menu-bar popover 800 × 920; contact sheet 3200 × 31062 pixels. |
| Visual review | Inspected shield, + duration sheet, selected saved custom chip, custom confirmation, Mac active popover, Mac groups window, website setup, iPhone remote lock needing picks and Mac sync error. Reviewed hierarchy, selected state, copy, scope and action placement. |
| `git diff --check` / `git diff --cached --check` | **0** before commit. |

All fixture values are synthetic. Links simulate transitions, not permission, persistence, filter activation or sync. Rendering at each reference viewport verifies design geometry; it does not establish native accessibility, flexible window sizing or Apple API behavior.

## Full applicable local CI

Ran the complete portable `tooling` job from `.github/workflows/ci.yml`. Each build/check shell sourced `.job.env` and prepended `$HOME/.cargo/bin` to PATH. Ruby was absent from the base environment; temporarily extracted Debian Ruby 3.3.8, its runtime and libyaml under the assigned worktree's `.ci-tools`, without installing packages or changing shared configuration. Removed the temporary runtime before commit. For Ruby checks the shell additionally set:

```sh
export PATH="$HOME/.cargo/bin:$PWD/.ci-tools/usr/bin:$PATH"
export LD_LIBRARY_PATH="$PWD/.ci-tools/usr/lib/x86_64-linux-gnu"
export RUBYLIB="$PWD/.ci-tools/usr/lib/ruby/3.3.0:$PWD/.ci-tools/usr/lib/x86_64-linux-gnu/ruby/3.3.0"
```

| Exact command | Exit / result |
| --- | --- |
| `ruby scripts/check-release.rb` | **0**; app selection, local/CI signing mechanics, next build, distribution/failure gates and listing checks passed without Apple access. |
| `python3 scripts/test-changed-apps.py` | **0**; initial/no-op/docs/app/shared/site/web/cross-app rename cases passed. |
| `python3 scripts/test-duo-screenshots.py` | **0**; all 16 tests passed. |
| `shellcheck scripts/*.sh apps/*/scripts/*.sh` | **0**. |
| `/home/box/go/bin/actionlint` | **0**. |

No registered app manifest, Swift package, shared code, template or admin code changed, so native app/RDesign/template/admin matrix gates do not apply to this diff. Blockr remains a design directory without `app.yml`. No macOS/Xcode simulator build, signed iPhone/Mac test, CloudKit account test, NetworkExtension test or native screenshot capture ran on this Linux box; none is claimed as passing.

## Research and remaining platform gates

Apple documentation, WWDC21/22/19/25 sessions and an Apple DTS Developer Forums response were consulted on 2026-11-01. [DESIGN.md](DESIGN.md) links the sources and separates documented token opacity/revocation from the unverified device-portability assumption. Framework overview versus symbol availability was checked via Apple's documentation JSON metadata: no native macOS picker/authorization/store/DeviceActivity pipeline is documented; some framework/store/monitor/report symbols list Mac Catalyst, which does not establish native Mac parity.

The Safari setup fixture is manual Screen Time configuration: Blockr has no documented API to write or expire those system rules. Timed Mac website locks require a separately validated native content-filter path. The custom browser block page is a cooperating-extension concept; a generic network filter cannot inject it into arbitrary HTTPS responses. Native Mac app blocking is explicitly unavailable in this pass.

Before implementation, validate all signed permission/token/expiry/report behaviors, Mac filter activation and supported-browser coverage, account changes/offline lock conflicts/partial coverage and native accessibility listed in DESIGN.md. These are implementation gates, not failures hidden by the mockup renderer.
