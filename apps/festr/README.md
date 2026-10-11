# Festr

A simple, iOS-native festival planner: upcoming US festivals, day-by-day set times, your own schedule with clash highlighting, lock-screen wallpapers and a Live Activity. SwiftUI on iOS 26 with Liquid Glass.

## Layout

| Path | What |
| --- | --- |
| `Festr/Core` | Pure Foundation logic shared by the app, widget extension and `swift test`: feed schema, local dates and time zones, clashes, Live Activity planning, feed cache/ETag client. |
| `Festr/Features` | SwiftUI screens: Discover, Festival timeline, My Schedule, Wallpaper studio, Live Activity controller and preview. |
| `Festr/Shared` | ActivityKit attributes and the Live Activity views used by both the app and `FestrWidgets`. |
| `FestrWidgets` | Widget extension: Lock Screen and Dynamic Island Live Activity. |
| `Festr/Resources/seed-feed.json` | Bundled feed, generated from `data/festivals.source.json` by `scripts/make-seed-feed.py`. |
| `Tests` | Unit tests (`swift test`). |
| `FestrUITests` | UI flow tests and screenshot capture. |
| `../../web/festr-admin` | Next.js + Drizzle + Postgres admin that edits festivals and publishes the feed. |
| `../../fastlane`, `app.yml` | Shared release automation; see [docs/RELEASE.md](../../docs/RELEASE.md). |

The shared design package is `../../packages/RDesign`. Run the following from `apps/festr`.

## Build and test

```bash
swift test                                   # core logic (also runs on Linux)
xcodegen generate                            # after editing project.yml
scripts/capture-screenshots.sh               # UI screenshots, light and dark (macOS, Xcode 26.2+)
RUN_FLOW_TESTS=1 scripts/capture-screenshots.sh build/screenshots/raw light
ruby scripts/check-release.rb                # fastlane lane mechanics, no Apple credentials
```

## Feed

Schema version 1 (see `Festr/Core/Feed.swift` and `../../web/festr-admin/src/lib/feed.ts`):

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-10-10T19:00:00Z",
  "festivals": [{
    "id": "head-trip-2026", "name": "Head Trip", "venue": "Empire Polo Club", "city": "Indio", "region": "CA", "country": "US",
    "timeZone": "America/Los_Angeles", "startDate": "2026-10-10", "endDate": "2026-10-11",
    "sourceURL": "https://lineupscout.com/head-trip", "updatedAt": "2026-10-10T19:00:00Z",
    "lineup": ["Calvin Harris"],
    "stages": [{ "id": "main", "name": "Main Stage", "sortOrder": 0 }],
    "sets": [{ "id": "…", "artist": "Calvin Harris", "stageId": "main", "day": "2026-10-10",
               "start": "2026-10-11T06:00:00Z", "end": null, "sourceURL": "…", "updatedAt": "…" }]
  }]
}
```

- `start`/`end` are UTC instants; `end: null` is an open-ended closer (assumed 90 minutes for progress and clashes).
- Times are displayed in the festival's `timeZone`. A set's festival `day` is explicit, or derived from its start with anything before 06:00 local counted as the previous night.
- The app bundles the seed feed and refreshes from `<FEED_BASE_URL>/feed/index.json` (`FEED_BASE_URL` build setting in `project.yml`, or the base URL field in About; unset means bundled only) with `If-None-Match`, caching the last good response on disk for offline use. A cached feed is used only if it is newer than the bundled one.

To change the bundled data, edit `data/festivals.source.json` (local wall-clock times) and run `python3 scripts/make-seed-feed.py`.

## Stopwatch

The Stopwatch tab offers Start/Stop, Lap and Reset. Laps are split durations and exclude paused time. Reset stops the timer and clears its laps. `Core/Stopwatch.swift` is a pure Codable model: elapsed time comes from a start date plus accumulated time, so it survives suspension and relaunch without a background ticking task.

`StopwatchStore` saves the full state in UserDefaults under `group.com.calumwebb.festr`. Both targets declare that App Group in `project.yml`; signing profiles must include it. LiveActivityIntent actions run through the same main-actor controller as the app. Activity updates are serialized and schedule refreshes merge the latest stopwatch summary (start date, accumulated time, last lap and count), keeping the activity payload bounded as the lap history grows.

The existing festival activity keeps current/next sets alongside the stopwatch. Without a festival activity, starting the stopwatch creates a stopwatch-only activity using the same attributes. Reset ends a stopwatch-only activity and leaves festival activities intact. Running elapsed text uses `Text(timerInterval:)`; paused text is static. The timer persists independently of the system's Live Activity lifetime.

Linux coverage includes pause/resume, lap splits, reset, Codable restoration, shared defaults, and payload size. On macOS/Xcode 26.2+, build both targets and verify on a device: start and lap from the app, use all Lock Screen/expanded Dynamic Island controls, relaunch while running and paused, and confirm a schedule refresh preserves the timer and laps. Check both a festival activity and a stopwatch-only activity. The Lock Screen preview uses synthetic timer data and disables its buttons.
