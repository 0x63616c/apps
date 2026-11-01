# Blockr v1 independent verification — APP-15

Reviewed APP-13 and APP-14 ticket bodies and the APP-13 design branch
`origin/APP-13-blockr-design-2` (`bc8273106556a24e68545b8b19cf70216ea3cd58`).
Design files were read with `git show`; none were modified. Paths below are relative
to `apps/blockr` unless prefixed with `/` (repository root). A source review is not
proof of enforcement by Apple services. This report does not certify a shipped release.

## Done-when audit

Each row preserves one ticket checklist item. Compound items explicitly separate
implemented evidence from remaining acceptance gates.

| Ticket/item | Status | Evidence and limits |
| --- | --- | --- |
| APP-13: rename apps/blocker and every product reference | pass | `apps/blockr` is the sole app path; `App/App.swift:8`, `app.yml:1`. “App Blocker” is a descriptive listing term; historical ticket/design references are not product naming. |
| APP-13: visual shield, one button, no footnotes | fixed in this PR | `Extensions/ShieldConfiguration/Configuration.swift:7`: icon, matching group, remaining-time snapshot, one Close action; no explainer. Corrected unrelated-group metadata during concurrent locks. Apple owns shield typography/caching; signed-device validation remains. |
| APP-13: sorted presets and + custom create/save/delete | fixed in this PR | `Sources/BlockrCore/Models.swift:22`, `App/Views.swift:175`, `App/Views.swift:306`; `testPresetsAndCustomDeduplication`, `testDurationBoundsAndNormalization`, `testDurationDeletionSync`. Default 2h, sorted saved preferences, edit/delete menu, built-ins protected. |
| APP-13: Mac window/menu/setup/active screens | fixed in this PR | `App/App.swift:16`, `App/MacFilter.swift:107`, `App/Views.swift:151`. Active title corrected; menu timer uses reference 58-point system type. Filter setup/health states exist; feature defaults unavailable, not enabled. Mac runtime/layout requires native capture. |
| APP-13: iCloud syncing/synced/off/signed-out/error/remote lock | fixed in this PR | `App/CloudSync.swift:8`, `App/Model.swift:226`, `App/StatsSettings.swift:36`, `App/Views.swift:258`. Added remote-origin label and disabled the unavailable sync toggle. All statuses mapped; default flag returns unavailable before constructing CKContainer. Live account transitions need signed devices. |
| APP-13: sourced DESIGN.md token-sync answer | pass | Design-branch `apps/blockr/design/DESIGN.md`, “Can picker selections sync across devices?” cites Apple selection/token documentation and WWDC21/22, distinguishes uncertainty from contract, retains local picks. `Replica` excludes selections; `testSyncPayloadNeverContainsTokens`. |
| APP-13: re-rendered PNGs and ordered contact sheet | pass | Read-only inventory check: all 118 PNGs exist and index order matches `screens.json`; design branch contains screenshots for its inventory, `screenshots/contact-sheet.png`, `index.html`, `render-report.json`. Contact sheet inspected read-only; delivery artifacts, not native screenshots. |
| APP-13: draft PR opened | pass | [Design PR #40](https://github.com/0x63616c/apps/pull/40), linked as draft in APP-13. Design delivery is not reimplemented here. |
| APP-14: universal app, IDs, extensions, app group, team | pass | `project.yml:1` sets iOS/macOS, team X9E4HG27NK; `project.yml:26` extension template, `project.yml:46` app identity; entitlements use group.com.calumwebb.blockr. Native build evidence below; distribution entitlements remain external. |
| APP-14: onboarding/auth/groups/uncancellable confirm/presets/custom | fixed in this PR | `App/Views.swift:54`, `App/Groups.swift:47`, `App/Model.swift:86`, `Shared/Enforcement.swift:90`. Mutation guards read current coordinated state. Repair unions immutable picks, preserves prior policy on failure and does not restart an existing monitor. `testNoSecondStartOrMutationDuringLock`, duration tests. System selection/authorization needs device acceptance. |
| APP-14: custom shield and ShieldAction | not verifiable without a signed device | `Extensions/ShieldConfiguration/Configuration.swift:7`, `Extensions/ShieldAction/Action.swift:4`. One button returns `.close`, records a tap without clearing protection. Relevant group selection fixed; fallback stays honest. Simulator tests cannot invoke genuine system shields. |
| APP-14: deny removal/settings lock/DeviceActivity expiry | not verifiable without a signed device | `Shared/Enforcement.swift:23`, `Shared/Enforcement.swift:66`, `Extensions/DeviceActivityMonitor/Monitor.swift:4`, `App/StatsSettings.swift:40`. Restore previous denyAppRemoval only after union expires; launch reconciliation does not claim successful continuity. Settings mutations/reset recheck live locks. Fixture capture passed, including locked Settings and the disabled reset assertion. Killed-app/reboot expiry and own-app exemption require device tests. |
| APP-14: on-device attempts/time saved/streak/per-app stats | out of scope -> follow-up | `App/StatsSettings.swift:4`, `Sources/BlockrCore/Models.swift:186`. Only shield-button taps, completed sessions and union time are measured. Blocked opens/time saved are —; per-app usage unavailable. No DeviceActivityReport extension or seven-day baseline exists. Signed report feasibility and a separate implementation ticket are required; this checklist is not complete. Fixed partial coverage being counted as an unbroken completion (`testPartialRepairCannotInventUnbrokenLock`). |
| APP-14: private CloudKit groups/locks; tokens local | not verifiable without a signed device | `App/CloudSync.swift:13` private DB, optimistic record save/retry, account detachment, durable local outbound queue; `Sources/BlockrCore/Models.swift:166` tombstone/revision/lock union tests. Tokens/receipts/attempts excluded by type. Defaults BLOCKR_CLOUD_ENABLED=NO; container/schema/profiles and two-device offline/conflict/account-switch tests outstanding. Revision exhaustion now throws instead of crashing. |
| APP-14: iOS web domains and explicit Mac setup | not verifiable without a signed device | `Shared/Enforcement.swift:60`, `ContentFilter/Provider.swift:17`, `App/MacFilter.swift:107`. iOS typed-domain filter plus token shields; Mac XPC health acknowledgement required. BLOCKR_FILTER_ENABLED=NO honestly prevents local Mac starts. Cross-browser/QUIC/DoH/VPN/expiry/provider-restart coverage is unverified. |
| APP-14: black Liquid Glass matching designs | fixed in this PR | `App/Views.swift:16`, `App/Groups.swift:75`, `App/App.swift:16`. Native tab/navigation/sheet chrome, opaque black content, monochrome chips. Removed routine website footer; restored compact Stats rows with definitions behind “About these stats”; added compact read-only locked Settings; corrected active title/menu type. See screen-by-screen audit below. Native accessibility/glass behavior still needs simulator/device review. |
| APP-14: core unit tests; CI iOS/macOS builds/tests | fixed in this PR | 22 Blockr tests pass on Linux Swift 6.2.1; `.github/workflows/ci.yml` builds both native schemes. Prior native run passed 20 tests and both builds. Final local startup-guard changes require wrapper publication/native CI; see evidence below. |
| APP-14: app.yml TestFlight ID/group/all extension targets | pass | `app.yml:6` apple_id 6829523373, group Internal, signed_targets includes app plus all three iOS extensions. Mac filter appears separately under macos_registration_targets; the shared release lane is iOS only, so Mac TestFlight packaging/distribution is a follow-up. `ruby scripts/check-release.rb` passes; this is wiring evidence, not delivery. |
| APP-14: merged with CI green | pass | [PR #41](https://github.com/0x63616c/apps/pull/41) merged as `32c875b6a301e514e6f27b2b5e2979ab9fb29060`; [successful app build/test run](https://github.com/0x63616c/apps/actions/runs/41352383413). Subsequent reruns/merge-push runs are separate from that successful pre-merge run. |

## Screen comparison

Reference geometry/palette reviewed from the branch contact sheet and DESIGN.md.
System-owned controls are constrained by Apple APIs. No synthetic HTML screen is
represented as a working system shield or a signed Mac filter.

| Implemented screen | Reference | Review result |
| --- | --- | --- |
| Home and groups | 06–08, 13 | Flat monochrome rows, system type, New group and bottom action; deletion confirmation in editor. Website-only groups no longer incorrectly request local app picks in GroupsView. |
| Group editor | 09–12e | Local picker and separate typed domains/category hint; save/discard/delete/error guards. Removed routine website footer. |
| Duration/custom/editor | 14–16d | Ascending elapsed durations, 2h default, + chip, inline validation, selected custom save/edit/delete. Native sheet replaces HTML geometry. |
| Confirm | 17–19 | Group/scope/duration/end and explicit commitment; duplicate starts disabled; start recomputes end. |
| Active | 20–23e, 43 | Prominent timer, locked title, honest partial/missing-protection controls; remote origin is explicit. |
| Shield | 22/22b/22c | Lock, group, remaining snapshot/end, one button; now matches the relevant local session. No footnotes. Real system typography/dismissal/cache needs device testing. |
| Stats | 24–27, 44 | Unavailable values stay unavailable; compact label/value rows replace oversized stacked metrics; definitions moved into disclosure. Report/per-app design remains a follow-up, not claimed parity. |
| Settings locked | 28–31, 45b | Compact locked rows replace the editable settings form; reset disabled with storage-level guard; recovery/read-only links remain usable. Missing protection remains actionable. |
| Mac window | 41–45 | Native sidebar and bounded content, no unsupported app picker; active title fixed. Needs native window screenshot/keyboard acceptance. |
| Mac menu bar | 40/40b | Idle/active, group/timer/protection status/window action; 58-point system timer corrected. Needs native popover screenshot acceptance. |
| Mac website setup | 46–47b | Activation, approval, error, enabled health states exist; unavailable by default. No injected HTTPS page or fabricated “Enabled”. |
| iCloud states | 32–36, 50–53 | Every status mapped, error details/last sync/retry retained, remote origin visible. Unavailable toggle disabled. Signed-out/error/network transitions await enabled signed builds. |

## Findings fixed

- Concurrent startup/reconciliation could overwrite pending receipts and clear another attempt’s policy. Installation IDs now reserve each attempt under coordinated storage; duplicate pending/active starts are rejected; completion/cleanup verify ownership. A 60-second lease separates in-flight startup from crash recovery. Fresh pending intent cannot apply shields before a monitor is registered, while repair retains installed coverage. Sync error handling preserves another process’s receipt. `testInstallationReservationRejectsConcurrentStartAndPreservesIdentity` and `testStartupRecoveryWaitsForLeaseAndLegacyReceiptsDecode` cover policy, recovery timing and old receipt decoding; real multi-process fault injection remains outstanding.
- Revision arithmetic could trap on a decoded Int64.max counter. Edits now fail with a visible error; regression test covers the boundary.
- Repair could replace session picks, restart its monitor and lose existing protection on failure. Picks now union with the original snapshot; existing monitors are retained; failure restores prior snapshot/receipt and reapplies the union.
- Partial coverage could become a successful unbroken completion after repair. Coverage history now retains incomplete protection permanently, preserves first application time and excludes it from completed/time/streak stats.
- Shield metadata used the latest lock even when an unrelated item was shielded. Match the local app/category/web token and installed coverage before selecting the latest relevant end; otherwise show unknown time (`testShieldUsesLatestRelevantLocalSession`).
- Removed the group-editor website footer, restored compact Stats rows with definitions in an optional disclosure, and made locked Settings a compact read-only screen. Corrected Mac active title and menu timer; added remote-origin state, disabled unavailable sync, and fixed unnecessary local-picks prompt on website-only groups.
- Restored the duration screen’s six-chip preset row, removed decorative marketing content, added the end-time preview and fixed the Review action at the bottom. Custom editor now scrolls with the keyboard and large text. Fixture save/edit/delete and selected-preset fallback tests passed in the linked capture.
- Added the active lock’s read-only group disclosure and full-unit duration accessibility labels, preserving selected traits and avoiding second-by-second timer announcements.
- Made Mac confirmation explicitly website-only, removed provisioning jargon from unavailable-filter copy, moved routine sync details into disclosure and reset details into its confirmation.
- Native CI exposed Mac delegate isolation warnings and an unsupported `filterBrowsers` setting. Delegate entry points now explicitly hop UI updates onto the main actor; native Mac filtering uses the supported socket path. Rebuild outcome is listed below.
- Captures exposed red app-owned delete/reset actions from destructive button roles. App-owned buttons/menus/dialog actions now use the monochrome tint; explicit delete/reset titles, confirmation dialogs and cancel actions remain. This final palette adjustment awaits wrapper capture. Added a 0.5-second screenshot settling delay after observing partially animated native glass/tab chrome.
- Extended fixture UI screenshots with locked Settings and a reset-disabled assertion.

## Checks and evidence

Local commands source `.job.env`, prepend `$HOME/.cargo/bin`, and use at most four Swift jobs.
Swift 6.2.1 was already installed under `~/.local/share/swiftly/toolchains/6.2.1` but
initially failed to start (missing libncurses.so.6). Debian libncurses/libtinfo were
extracted privately under this worktree for LD_LIBRARY_PATH. Ruby 3.3.8/libyaml were
also extracted privately; no shared configuration was changed. The initially available
`/tmp/www66/bin/actionlint` later disappeared; final checks used a private copy of
CI’s actionlint v1.7.7 instead. These tools are not committed.

| Command | Result |
| --- | --- |
| `swift test --package-path apps/blockr --jobs 4` | exit 0; 22 tests |
| `swift test --package-path packages/RDesign --jobs 4` | exit 0; 3 tests |
| `ruby scripts/check-release.rb` | exit 0 |
| `python3 scripts/test-changed-apps.py` | exit 0 |
| `python3 scripts/test-duo-screenshots.py` | exit 0; 16 tests |
| `shellcheck scripts/*.sh apps/*/scripts/*.sh` | exit 0 |
| `actionlint` (private v1.7.7 binary) | exit 0 |
| `git diff --check` | exit 0 |

| Native evidence | Result |
| --- | --- |
| [CI for 87a8a81](https://github.com/0x63616c/apps/actions/runs/41354293433) | success: tooling, 20 macOS core tests, iOS simulator build, native macOS build. Generated project artifact matches the checked-in project byte-for-byte. Mac delegate/unsupported-setting warnings prompted the subsequent fix. |
| [CI after Mac delegate fix, 793d9a9](https://github.com/0x63616c/apps/actions/runs/41354671053) | success: tooling, 20 core tests, iOS simulator build and macOS build. No MacFilter.swift warnings remain. |
| [APP-15 fixture capture, 87a8a81](https://github.com/0x63616c/apps/actions/runs/41354351134) | success: both UI tests passed; 12 PNGs downloaded. Reviewed home/groups, new group, duration/custom/edit/saved, confirm, active, Stats and Settings/locked Settings. Final monochrome action roles and screenshot settling delay are later local adjustments and need wrapper recapture. |
| Final local changes | Linux core tests: 22 pass. Native build/capture not run for local startup guard, monochrome action roles and screenshot settling adjustment; wrapper must publish and run CI under the replacement publishing rules. |
| [Before fixture capture](https://github.com/0x63616c/apps/actions/runs/41352121351) | success; `pr-screenshots/blockr/light/` downloaded and reviewed (home, stats, custom duration, active). |

Native commands in the successful published CI runs (exit 0; these are not final-local-revision results):

```sh
xcodebuild -project apps/blockr/Blockr.xcodeproj -scheme Blockr -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project apps/blockr/Blockr.xcodeproj -scheme BlockrMac -destination 'generic/platform=macOS' -configuration Debug -jobs 4 CODE_SIGNING_ALLOWED=NO build -quiet
scripts/capture-screenshots.sh blockr build/pr-screenshots/blockr light
```

The capture artifact is `pr-screenshots`, with files under `blockr/light/`:
`home.png`, `groups.png`, `group-new.png`, `duration.png`, `custom-duration.png`,
`duration-saved.png`, `duration-edit.png`, `confirm.png`, `active.png`, `stats.png`,
`settings.png`, `settings-locked.png`. Compact rows and the duration hierarchy were
visually checked against the references. Native glass/status/tab chrome is transient
in some captures; the added settling delay needs a new wrapper capture.

Superseded queued runs cancelled during implementation are not counted as successful
checks. After the publishing-rule update, further pushes, workflow control and PR
publication belong to the wrapper. Existing run outcomes are observed read-only.

The concurrency assumptions were also checked against Apple’s documentation for
[CKDatabase.save](https://developer.apple.com/documentation/cloudkit/ckdatabase/save%28_%3A%29-1j6fq)
and [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator).
The former documents version-checked saves; the latter coordinates access across
processes. This supports the inspected design, not a claim that multi-process
fault injection or live CloudKit conflicts passed.

## Remaining acceptance gates

Family Controls (Distribution) must be enabled externally on the app and three iOS
extension IDs. The existing profile entitlement gate is unchanged. No TestFlight
success is claimed; the known [signing failure](https://github.com/0x63616c/apps/actions/runs/41350496157)
is external. Apple ID/group wiring is not internal-tester availability.

Signed acceptance still needs authorization denial/revocation/reapproval; removal
restoration; own-app exclusion/category overlap; concurrent shields and repair
failure; expiry while app is killed/rebooted; DST/time-zone/clock changes; CloudKit
account/offline/conflict/two-device delivery; Mac activation/health/restarts,
browser transport and VPN coverage. Force unwraps in app sources are constant URLs
or GMT time zone, not external data. Storage coordination/atomic replacement and
corruption refusal were inspected; multi-process fault injection remains a signed
integration gate. UI fixture tests cannot prove extension or service enforcement. Native Mac UI captures remain outstanding. Twelve iOS fixture captures passed at 87a8a81; they reveal the red actions and transient chrome addressed by subsequent local changes, so final palette/timing acceptance still needs wrapper recapture.

Product follow-ups are the missing privacy-preserving stats report/baseline and
Mac TestFlight distribution. Native VoiceOver, Dynamic Type, Reduce Transparency,
keyboard/focus and long-name acceptance remain outstanding; source labels alone
are not a completed accessibility audit. Do not mark these gates passed from CI compilation.
