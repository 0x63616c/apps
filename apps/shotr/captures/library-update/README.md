# Library, hiding, and scan progress revision

Native iOS 27.0 (24A434) screenshots on an iPhone 16 Pro simulator, September 27, 2026. Generated sample images only; no personal Photos data.

- `library-light.png`: title at top left and continuous grid.
- `grouped-by-day.png`: date headers and per-day counts.
- `search-expanded.png`, `search-results.png`: native floating glass search, with title/count preserved.
- `hidden.png`: reversible hidden-item view.
- `scan-progress.png`, `scan-paused.png`, `scan-timing.png`: six-image native interaction test using real Vision/local AI plus a deliberate 700ms fixture image delay. These illustrate controls, not performance.
- `benchmark-completed.png`: library after the unthrottled scan.
- Other PNGs retain the tag/gallery regression captures.

The clean 15-image benchmark completed in 62.75s with no failures. See benchmark.json: 11.06s Vision, 51.45s local AI. No artificial delay or pause. Uses 600×1000 generated images, in-memory fetch, and bypassed persistence. These numbers are simulator measurements, not iPhone/PhotoKit/iCloud performance guarantees.

18 core tests pass. Four native UI flows passed across the initial suite (three flows) and corrected focused scan test. UI evidence checks title alignment, native search, gallery, icon edits, day layout persistence, hide/unhide, scan progress/pause/resume and accessible final count. Physical-device behavior and real saved-index relaunch remain separate gates.
