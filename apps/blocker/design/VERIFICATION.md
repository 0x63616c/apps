# Design verification — APP-11

Design artifacts only; no Swift, app project, entitlement, app manifest, shared component or production website changed.

## Artifact checks

| Command / inspection | Result |
| --- | --- |
| `python3 apps/blocker/design/build.py` | Exit 0; 56 standalone HTML screens, inventory and contact sheet generated. |
| `PLAYWRIGHT_MODULE=/tmp/wk2/node_modules/playwright node apps/blocker/design/render.mjs` | Exit 0; headless Chromium captured 56 PNGs and a full contact-sheet PNG. External existing Playwright install, not a repo dependency. |
| HTML link / PNG validation using Python `HTMLParser` and PNG header inspection | Exit 0; local HTML references resolve; all 56 screen PNGs are 804 × 1748. |
| [render-report.json](render-report.json) | No runtime/resource errors, no content overflow and no out-of-frame elements at 402 × 874. |
| Visual inspection | Welcome, group editor, confirmation sheet, active home, shield, stats and locked settings inspected as rendered PNGs. Hierarchy, copy and action placement reviewed. |
| `git diff --check` | Exit 0 before commit. |

## Repository checks

Commands ran from the assigned worktree with `.job.env` sourced and `$HOME/.cargo/bin` prepended to PATH.

| Exact command | Exit / result |
| --- | --- |
| `ruby scripts/check-release.rb` | **127 — blocked locally:** `ruby: command not found`. Release lane checks did not run. |
| `python3 scripts/test-changed-apps.py` | **1 — blocked locally:** its `scripts/changed-apps.sh` subprocess exits 127 because Ruby is absent. Path-filter checks did not complete. |
| `python3 scripts/test-duo-screenshots.py` | **0 — passed:** 16 tests. |
| `shellcheck scripts/*.sh apps/*/scripts/*.sh` | **0 — passed.** |
| `actionlint` | **127:** executable absent from PATH. Located the existing binary before retrying. |
| `/home/box/go/bin/actionlint` | **0 — passed.** |

The Ruby checks must run in GitHub CI, which has Ruby. No check was disabled or changed. This is not a claim that full local CI passed.

No native app or shared Swift code changed, so Swift package gates do not apply to this design diff. Swift and macOS/Xcode are unavailable in this Linux environment. Native builds, real Screen Time permissions/extensions, deletion restrictions, automatic expiry and native accessibility behavior have **not** been tested. No simulator screenshot is claimed. The native/device validation checklist is in [DESIGN.md](DESIGN.md).
