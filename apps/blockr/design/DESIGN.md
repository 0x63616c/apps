# Blockr — design pass 2

[APP-13](https://tickets.worldwidewebb.co/t/APP-13) · supersedes APP-11 · design only

Product name: **Blockr**. App Store name: **Blockr: App Blocker**. One universal product for iPhone and Mac, with platform-specific capabilities. No app project, Swift implementation, entitlement or cloud service is created here.

Open [index.html](index.html) for the labelled contact sheet in flow order. [screens.json](screens.json) is the inventory and source of capture dimensions: iPhone 402 × 874, Mac window/browser 1120 × 760, menu-bar popover 400 × 460 CSS pixels, all captured at 2×. All selections, device names, dates and numbers are synthetic. HTML expresses design intent; system prompts, pickers and shields are illustrations, not native screenshots.

## Flows

| Flow | Review states |
| --- | --- |
| Setup | `01`–`05b`: explanation, individual Screen Time approval, declined, help, error |
| Groups | `06`–`13`: empty/multiple/ready, new/edit, typed domain entry, picker/category/empty search, validation/save error, cleared selection, discard/delete |
| Duration | `14`–`17`: default 2h, group choice, every preset, + sheet, validation, saved custom chip, edit/delete, confirmation for each duration/category |
| During lock | `18`–`23e`: applying/failure, active/read-only, app/web/fallback shields, completion, revoked access, delayed expiry/recovery, reselect |
| Stats/settings | `24`–`31`: report/empty/loading/error/explanation, editable/locked settings, local data deletion/error, About |
| iCloud on iPhone | `32`–`36`, `11d`/`11e`: syncing/current/off/signed out/error, Settings handoff, remote lock, group needs local apps, picker, ready, partial coverage |
| Mac | `40`–`46d`: idle/active popover, groups/editor/new, start/presets/custom/edit/confirm, active/read-only, stats, settings/locked, content-filter setup/enabled/error, manual Safari Screen Time |
| Browser | `47`, `47b`: proposed cooperating-browser blocked page and network-denial fallback |
| iCloud on Mac | `50`–`53`: all five status states, Settings handoff, remote lock, group needs Mac setup, remote lock without protection |

The contact sheet uses explicit flow ordering for duration and sync states. `11d`/`11e` belong with iCloud, not initial group creation. Rebuilding deletes HTML/PNGs absent from the inventory so stale states cannot survive. Static links are review transitions: saving, granting permission, opening Settings and retrying do not perform those actions. Each duration has its own review screen; final Start transitions converge on one representative 2h active fixture. Native runtime guards must preserve the actual chosen duration and authorization state.

### Start, duration and commitment

Choose a group → duration → review → explicit Start. Default is **2h**, regardless of the last long lock. Presets are always **1h, 2h, 4h, 1d, 3d, +**, ascending by elapsed seconds. A day is 24 hours, including across daylight-saving changes.

The + chip opens a compact three-field days/hours/minutes sheet. Save normalizes to elapsed seconds, deduplicates equal durations and inserts the new chip in ascending order, selected. The fixture saves **1h 30m / 1.5h**, between 1h and 2h. Saving does not start a lock. Cancel retains the prior selection. Custom duration range is 15 minutes to 7 days; reject empty, negative, fractional, zero and out-of-range totals inline. Maximum is a total, not seven days plus extra hours. A duplicate selects the existing chip; built-in presets cannot be deleted.

Long-press a saved chip opens Edit / Delete / Keep; **Edit saved duration** provides the same path for keyboard and assistive technology. Editing prepopulates the sheet; saving re-sorts, including moving the chip if necessary. Deleting the selected custom chip returns to 2h; deleting another retains the current choice. Chip changes sync as preferences, never mutate an active lock. The same behavior has Mac fixtures, with secondary-click as the contextual-menu equivalent.

Confirmation repeats group, scope, duration and absolute end time, then “No cancelling once started.” Recompute the end instant at Start, preserving duration rather than an old preview time. Persist immutable selection/session snapshots and a stable session ID; register the iPhone monitor before applying shields. Disable duplicate starts. Show Active only after local setup succeeds. If rollback cannot be verified, remain in reconciliation; the “Nothing is locked” error fixture is only valid after verified cleanup.

Only one lock may apply locally. All group edits, settings mutations and local-data deletion are unavailable while it runs. Guard deep links and stale sheets as well as visible navigation. Stats stay readable. No early-unlock, extension or pause control. Device owners can still revoke permissions or remove system filters outside Blockr; no absolute tamper resistance is promised.

### Shields and expiry

[22-shield](22-shield.html) is a lock icon, group name, large remaining-time hierarchy, compact end time and **Close app**. The web version has **Close website**. No explainer, reassurance or footnote. Missing metadata uses [22b](22b-shield-fallback.html): lock, “Locked”, unknown time and **OK**, rather than inventing an end time.

On iPhone, `ShieldConfiguration` owns typography and layout. Its title/subtitle carry the group and a snapshot such as “1h 42m left · until 11:41 am”; the oversized HTML timer is a hierarchy reference, not a promised custom system font or live countdown. A shield configuration can be cached. One primary action returns `.close`; it never clears restrictions or opens Blockr. Validate fallback system labels and dismissal on device. [Apple’s shield configuration](https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration) and [action response](https://developer.apple.com/documentation/managedsettings/shieldactionresponse) define this boundary.

At expiry the iPhone monitor clears this session’s fields and restores the previous app-removal value in Blockr’s named store. Do not clear other apps’ restrictions. Reconcile persisted absolute times on launch and after reboot; never reapply an expired remote record. Late callbacks are not an exact-second guarantee. Uncertain continuity is interrupted, never a successful streak entry. The expired-lock recovery action cannot be used before expiry.

## Can picker selections sync across devices?

**Do not ship cross-device token replay as a supported feature.** Apple documents `FamilyActivitySelection` as opaque application/category/web-domain values and explicitly says authorization revocation voids its tokens. Codable persistence is not a portability contract. This applies to `ApplicationToken`, `ActivityCategoryToken` and `WebDomainToken`; do not decode identities, infer bundle IDs or scrape token-backed labels. [FamilyActivitySelection](https://developer.apple.com/documentation/familycontrols/familyactivityselection), [Token](https://developer.apple.com/documentation/managedsettings/token).

**Documented versus unknown:** WWDC21 describes privacy within a Family Sharing group and parent/child control across devices. WWDC22 adds individual authorization; neither session establishes that independently authorized devices on one Apple Account can exchange selections. Calling tokens strictly “per-device” is therefore a conservative engineering assumption, **not a documented universal statement**. Their exact scope, same-account iPhone-to-iPhone replay and long-term portability remain unverified; the family authorization scenario must not be generalized to personal sync. [WWDC21: Meet the Screen Time API](https://developer.apple.com/videos/play/wwdc2021/10123/), [WWDC22: What’s new](https://developer.apple.com/videos/play/wwdc2022/110336/).

Developer Forums provide additional caution, not a specification: Apple DTS identifies a token-mismatch report as a bug and recommends reselection at the user level. That report is evidence of lifecycle fragility, not proof of a per-device cryptographic scope. [Apple Developer Forums, thread 758325](https://developer.apple.com/forums/thread/758325).

**Resulting design:** local app/category/domain tokens remain on the device that authorized and picked them. Sync group identity/name, **user-authored category intent** (for example a separately entered “Social” hint), typed web domains, duration preferences, schedule intent and active lock timestamps. A category hint is not an exported opaque category identity and does not silently select a local category. On a second iPhone show “Choose on this device”; approval/picking happens locally. Revocation or invalid tokens clears local readiness and requires reselection while keeping group metadata. Native macOS has no supported picker/authorization path described below, so iPhone-to-Mac token replay is not a viable foundation regardless of sync transport.

A signed two-iPhone investigation may later test token portability under independent authorization, family versus individual scope, revocation/reapproval and OS updates, but must not replace an Apple-supported contract. No such test was run for this design.

## Platform API mapping and Mac limits

Availability checked 2026-11-01 against Apple’s documentation metadata (`https://developer.apple.com/tutorials/data/documentation/<symbol>.json`) and linked symbol pages. Framework-level availability and individual APIs differ; **Mac Catalyst is not native macOS**.

| API | Documented platform availability relevant here | Design consequence |
| --- | --- | --- |
| [FamilyControls](https://developer.apple.com/documentation/familycontrols) | Framework overview lists iOS/iPadOS/Mac Catalyst 15+. [AuthorizationCenter](https://developer.apple.com/documentation/familycontrols/authorizationcenter) and [FamilyActivityPicker](https://developer.apple.com/documentation/familycontrols/familyactivitypicker) list iOS/iPadOS 15+, no native macOS or Catalyst. | Do not promise a Mac picker or local authorization because the framework overview mentions Catalyst. iPhone picks stay local. |
| [ManagedSettingsStore](https://developer.apple.com/documentation/managedsettings/managedsettingsstore) | iOS/iPadOS/Mac Catalyst 15+; no native macOS. | No documented native Mac shield store. Catalyst symbol availability alone does not establish an operational Mac permission/enforcement pipeline. |
| [DeviceActivityCenter](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter) / [Report](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport) | Center iOS/iPadOS/Mac Catalyst 15+; report 16+; no native macOS. | No native Mac monitor expiry or Screen Time usage-report parity. Mac stats show app-owned completed-lock history/time locked; unavailable app usage stays blank. |
| [Screen Time / STWebpageController](https://developer.apple.com/documentation/screentime/stwebpagecontroller) | Native macOS 11+, alongside iOS-family platforms. | A browser reports its pages and reacts to existing Screen Time restrictions. This is **not** a public write API for Blockr to install Safari-wide domain rules. |
| [NetworkExtension content filter](https://developer.apple.com/documentation/networkextension/filtering-network-traffic) | Native macOS filter-provider path, separate entitlements, user approval and system-extension lifecycle. | Proposed timed Mac website enforcement, with explicit setup and health states. No claim of desktop app launching restrictions. |
| [CloudKit sync](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app) | iPhone and Mac private DB, app-managed local replica with CKSyncEngine. | Same product and records; capability and enforcement state remain per device. |

### Mac website setup and browser experience

The requested “Safari through Screen Time web domains” is represented honestly as a **manual system setup** in `46d`: the person configures macOS Screen Time web-content restrictions. Blockr cannot write or expire those rules using `STWebpageController`; they are separate from timed locks. A future Apple-supported write API could change this. Apple’s own Screen Time sync must not be confused with Blockr’s CloudKit data.

For timed Blockr locks, propose a native NetworkExtension content filter covering supported traffic, including Safari, with one-time approval. `46` → `46a` → `46b` shows needs-setup, System Settings handoff and enabled; `46c` shows filter failure. Current settings route: General → Login Items & Extensions → Network Extensions, plus the system content-filter approval prompt; verify exact OS wording during implementation. Only mark enabled after provider activation/configuration and health checks, not after opening Settings. A disabled or failed provider prevents a new Mac lock. An arriving remote lock shows `53` until local setup is ready; it must not say “protected.”

Use `NEFilterManager`/`NEFilterDataProvider` and the supported system-extension activation mechanism with the appropriate signed entitlements/distribution profiles. No hosts-file edits, packet-filter hacks or TLS interception. Match normalized typed hosts/subdomains with explicit policy; verify international domains, DNS/DoH, encrypted host information, QUIC, private browsing, VPN coexistence and each supported browser before claiming coverage. Provider must persist end timestamps and stop denying expired sessions independently of the foreground UI, then reconcile after restart. Its feasibility, expiry and review approval are **unimplemented gates**, not a solved Screen Time substitute. [Apple’s Mac filter sample](https://developer.apple.com/documentation/networkextension/filtering-network-traffic), [WWDC19: Network Extensions for the Modern Mac](https://developer.apple.com/videos/play/wwdc2019/714/), [Network Extensions entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension).

`47-browser-blocked` is a proposed page for a cooperating browser extension that can navigate to its own local blocked-page UI. A network filter only allows/drops traffic and cannot inject this custom page into arbitrary HTTPS responses. `47b` sketches the fallback denied-connection experience with a conceptual route to Blockr; an unintegrated browser owns its actual error page and cannot be guaranteed to show that link. System Screen Time also owns its own Safari block presentation. Browser extension distribution and navigation behavior require a separate spike; no browser extension exists in this PR. [WWDC25: Filter and tunnel network traffic](https://developer.apple.com/videos/play/wwdc2025/234/) explains flow filtering and the separate newer URL-filter approach. That newer API requires additional infrastructure/participation and is not silently assumed here.

Mac desktop app blocking is explicitly unavailable in these designs. A separately reviewed enforcement mechanism would be needed before adding a native app picker, shield or deletion protection. Universal product identity does not imply identical OS capabilities.

## iCloud model and recovery

Use a CloudKit **private database**, one app container, a custom record zone and a durable local replica. `CKSyncEngine` handles eventual sends/fetches; preserve its serialized state. No public database, separate Blockr account or synchronization of protected usage reports. [Apple’s CloudKit architecture guidance](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app), [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5).

| Record / local state | Fields and rules |
| --- | --- |
| Group (synced) | Stable UUID, name, user-authored category-intent text, normalized typed domains, revision/tombstone. No token bytes or resolved private app labels. |
| DurationPreference (synced) | Elapsed seconds as deduplication key; custom/preset distinction; tombstone for custom removal. |
| ScheduleIntent (synced model only) | Group revision, time zone, recurrence semantics, future duration. No schedule editor added by this pass; each device must authorize and install local enforcement before readiness. |
| Lock (synced) | UUID, origin device alias, immutable group/domain intent snapshot, UTC start/end, interruption/completion facts; no remote opaque picks. Never infer local enforcement from receiving a record. |
| Device selection (local only) | Group UUID → authorized opaque token sets, authorization epoch/readiness, local policy revision. Revoke/reselect invalidates this mapping. |
| Enforcement receipt (per device) | Session ID, applied capability/scope, pending/active/failed/interrupted, last acknowledgement. Status cannot imply coverage of offline or unprepared devices. |

Offline local locks may start with a valid local selection/provider. They expire locally without iCloud. Offline writes queue; a sync failure never clears or extends protection. On arrival, ignore expired sessions; otherwise apply the remaining interval to this device’s saved picks and supported domains. `33`/`51` show a remote lock only **after** local application succeeds. `36` shows website-only partial protection with an app-picking action; `53` shows no Mac website protection until setup. If less than the OS minimum monitoring interval remains, keep pending/unprotected for that unsupported scope rather than secretly extending the lock; expired records never start anew. Failure and partial coverage must remain visible until reconciled.

Merge concurrent group edits using revision/change tags and retry conflicts; active lock snapshots remain immutable. Group deletion cannot delete an active lock. For offline concurrent lock starts, retain both immutable intents, enforce the union of supported scopes and release each at its own original end; display the latest end locally without claiming a single globally serialized start. Reconcile duplicates by UUID. Never shorten a still-live lock through last-writer-wins metadata. A conflict/coverage receipt is app-owned metadata, not proof of enforcement on an unreachable device.

Both platforms show **Syncing**, **Up to date**, **iCloud off**, **not signed in**, **sync error**, **remote lock arriving** and **group needs local setup**. CloudKit cannot reliably distinguish a disabled app-level switch from every account/service failure: present the known cause when available; otherwise use the generic error state. Up to date means the local queue and last fetch succeeded, not that every device acknowledged protection. Show last successful sync on error; retry preserves local data. [CKAccountStatus](https://developer.apple.com/documentation/cloudkit/ckaccountstatus).

Sign-out/account change detaches the old private replica/queued writes so another account never receives them; active local enforcement still runs to its persisted end. Local reset removes only this device’s replica/unsynced changes, never remote groups or active protection, and synced groups can return on the next sync. Device-specific app picks must be renewed after reset. No protected app usage or report-derived names travel via CloudKit.

## iPhone enforcement and stats

Use individual `FamilyControls` authorization, `FamilyActivityPicker`, a named `ManagedSettingsStore`, `DeviceActivitySchedule` and monitor extension. Apply app/category/domain token policies from the immutable local snapshot; separately typed domains require validation and a supported local web-domain policy. Deduplicate overlapping categories/apps. App removal is a device-wide `application.denyAppRemoval` value, not a per-selected-app switch; restore the prior value at expiry. Do not shield Blockr itself. Request Family Controls distribution approval for the app and each applicable monitor/report/shield-configuration/shield-action extension before planning release. [Family Controls entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement), [ApplicationSettings](https://developer.apple.com/documentation/managedsettings/applicationsettings), [DeviceActivitySchedule](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule).

Stats on iPhone use `DeviceActivityReport` within its privacy boundary. Keep private labels, usage and computation in the extension; do not export them into app storage or CloudKit. Blocked-open attempts remain **—**, since shield callbacks/taps are not a reliable launch event stream. Estimated time saved requires seven valid baseline days in matching local-time windows, deduplicated selected activity and actual lock-window usage: sum `max(0, baseline − actual)` over eligible activities. Missing baseline, changed selection or inaccessible reports produce unavailable, never zero. The sample 24m + 12m + 6m = 42m is synthetic and conditional on a real-device feasibility check. “Unbroken locks” counts locally completed sessions with no observed interruption, not calendar days or proof against bypass. Detailed definitions live in `27`; routine screens carry no small-print disclaimers. Mac displays completed locks/time locked, not invented Screen Time estimates. [DeviceActivityReport](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport).

## Visual system and accessibility

Keep the Vercel-like black canvas, flat rows and Liquid Glass control layer from pass 1. No green, teal, gradients, branded app imagery or external fonts. Material blur is limited to navigation/sheets/popover chrome; content stays opaque. System typography on Apple platforms, browser system sans fallback in these captures.

| Token | Value / role |
| --- | --- |
| Background / surface / raised | `#000` / `#141414` / `#242424` |
| Separator / primary / secondary / quiet | `#333` / `#fafafa` / `#aaa` / `#777` |
| Glass | `rgba(35,35,35,.86)`, subtle white edge, 24–28px blur |
| iPhone type | Title 34, sheet 30, section 22, body 16/24, timer 64–66 tabular |
| Mac type | Title 38, timer 92, popover timer 58, body 16 |
| Space | 4/8/12/16/20/24/32/40; phone inset 24, Mac content 56, sidebar 224 |
| Geometry | Field 12, chip 14, primary action 18, sheet 32, Mac window 16 |
| Targets | Minimum 44px; primary 54px; selected chip white fill, dark text and explicit selected semantics |

iPhone remains a focused vertical flow; Mac gains persistent sidebar and window chrome, not a stretched phone. The timer is the prominent element during a lock. No marketing copy, footnotes or incidental notes in routine screens. Validation, permission failures and missing protection retain the actionable words needed at that moment.

Native implementation must support Dynamic Type, long group names, localization, VoiceOver, keyboard navigation, secondary-click/context menus and visible focus. Announce “1 hour 30 minutes selected” and “1 hour 42 minutes remaining,” never each second. Meaning is carried by text/shape, not color. Respect Reduce Transparency/Increase Contrast with opaque surfaces, Reduce Motion with native minimal transitions. HTML captures establish reference geometry only; they do not validate native accessibility or the system shield’s actual typography.

## Reproduce and outstanding gates

```sh
python3 apps/blockr/design/build.py
PLAYWRIGHT_MODULE=/path/to/playwright node apps/blockr/design/render.mjs
python3 apps/blockr/design/verify.py
# Optional: CHROME_BIN=/path/to/chrome
```

The renderer uses the per-screen viewport and records runtime/resource failures, content overflow and out-of-frame content, then captures the full contact sheet. [render-report.json](render-report.json) and [VERIFICATION.md](VERIFICATION.md) contain delivery evidence. No server or application dependency is required.

Before implementation claims readiness: signed iPhone permission/revoke/reselect, tokens and typed domains, global app-removal restoration, shield caching/metadata/dismissal, expiry with app killed/rebooted/clock changed, baseline-report feasibility/privacy; signed Mac filter activation/revocation/health/expiry across browsers and VPNs; account switching, offline concurrent locks, missing picks, delayed delivery and near-expiry sync; native keyboard/VoiceOver/Dynamic Type. No on-device, simulator, CloudKit or NetworkExtension behavior is verified by this design PR.
