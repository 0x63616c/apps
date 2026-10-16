# Monorepo migration verification

Verified on Linux on 2026-10-10. All changes remain local on branch `monorepo`; no push, Pages publication, repository rename, App Store upload or remote mutation was performed.

| Check | Result |
| --- | --- |
| Swift 6.2: RDesign portable tests | 3 passed (frame configuration, path/appearance validation, spacing) |
| Swift 6.2: Tendr core | 34 passed |
| Swift 6.2: Shotr core | 46 passed |
| Swift 6.2: Festr core | 31 passed |
| Shotr release-tool Python tests | 15 passed |
| Festr seed feed consistency | Passed |
| Festr admin `bun install --frozen-lockfile` | Passed, bun 1.4.2 |
| Festr admin `bun run build` and `bun run lint` | Passed |
| Festr admin `bun run test` | 49 passed |
| `ruby scripts/check-release.rb` | Passed: app selection, signing, separate widget profile, project restoration, build numbering, test/provisioning failure gates and listing checks |
| actionlint 1.7.7 | All root workflows passed |
| ShellCheck 0.10.0 | Root and app shell scripts passed |
| Job timeout audit | Every root workflow job has `timeout-minutes` |
| `python3 scripts/test-changed-apps.py` | Passed: initial push, no changes, docs, app, shared, site, web, cross-app rename |
| XcodeGen 2.44.1 | Built on Linux; generated Tendr, Festr and a temporary scaffold project |
| Scaffold | Placeholder substitution, generated project/package reference and duplicate-name rejection passed |
| Import helper | Local fixture imported with original ancestor reachable; admin relocation passed |
| Source history | Both complete source tips are ancestors of this branch through non-squashed subtree merges |
| Pages preview | Original Tendr privacy/support documents mirrored at root; all app pages present; redirect stub generated |
| Live Tendr pages | Read-only HTTP checks returned 200 for existing `/tendr/privacy/` and `/tendr/support/` URLs |
| `git diff --check` | Passed |

Source tips: Shotr `75d0bdcdda8c5df53f90e6db757ee4e37b55d0e5`; Festr `b38b3129f904946c504146488d2b4ddc6cf08c2e`. Imports used complete temporary GitHub clones because the workspace source clones were shallow. The source repositories were only read.

Swift and actionlint were installed under `/tmp`; Ruby and ShellCheck were installed for these checks. Swift caches were redirected into `/tmp`. The Linux-built XcodeGen binary was invoked directly from the repository root with `--spec`; invoking it through PATH from a temporary scaffold directory hit a Linux Foundation bundle lookup crash. The successful direct invocation generated all three projects. A sandboxed Next.js rebuild initially failed to open its worker port; clearing generated `.next` output and rerunning with permitted execution completed successfully.

Still requires macOS/Xcode 26.2+ or Actions:

- Compile SwiftUI, StoreKit, AppKit/rframe and all iOS targets, including Festr’s widget.
- Run simulator UI/StoreKit tests and inspect launch screens and regenerated screenshots.
- Verify Shotr’s renamed product on a simulator/device and physical-device Photos behavior.
- Execute path-selected Actions jobs on the configured runner and verify Apple signing, processing and internal-group distribution.
- Publish the staged Pages layout when authorized. Test the rename/redirect switch only when the repository rename is authorized.

Shotr and Festr automatic TestFlight flags remain false pending native/release setup. Tendr remains enabled. Passing these Linux checks does not prove TestFlight availability.
