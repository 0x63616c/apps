# Shots — goal and acceptance spec

## Goal
Build the simplest useful native iPhone screenshot organizer: open it, see existing screenshots, find one by searching or tapping a tag. All image analysis runs on the iPhone. No account, server, ads, subscriptions, or premium features.

## Confirmed decisions
- Swift and SwiftUI. iOS 26 or later. Automatic tagging requires an Apple Intelligence-compatible iPhone with Apple Intelligence enabled and its model downloaded.
- Read existing screenshots from Apple Photos using PhotoKit. Keep originals there; store only the local search index and tag assignments.
- A screenshot can have multiple tags. AI may choose only from the user's fixed, editable tag list. It must never invent tags.
- Allow creating, renaming, deleting, assigning, and removing tags. Keep manual choices when rescanning.

## Product requirements
1. A single home screen with a Photos-style three-column grid, newest screenshots first, narrow gutters, no cards or captions. Title at top left with a numeric-only result count; a menu switches between a continuous grid and date sections with sticky day headers. Reuse cells for large libraries rather than mounting the entire library.
2. Search screenshot text, generated titles, visual labels, and tag names. Search and tag filters work together. Matching ignores case and accents, and supports multiple words.
3. A compact horizontal tag filter with All and Untagged. Icons sit to the left of labels, using a searchable shared collection for people and model context. No dashboard, counters on every tile, or extra navigation tabs.
4. Tap a screenshot for a full-screen, swipeable viewer with a bottom thumbnail gallery and zoom. Keep the current thumbnail centred as pages change, including the first and last image. Share and Tags use separate buttons, not a shared glass group. Reuse visible pages for large libraries. Offer rescanning and deletion through familiar system controls.
5. Support reversible, app-local hiding with a Hidden view and Unhide action; preserve originals and assignments. Support batch tag changes, batch rescanning, and batch deletion. Deleting an original requires explicit confirmation and uses the Photos deletion API.
6. Index the existing library on first access. Refresh on return to the app and when Photos changes. Resume unfinished analysis; do not reprocess everything on every launch. Show a progress bar, elapsed time, approximate remaining time, and pause/resume; retain a completed timing breakdown.
7. Rescan one, selected, or all screenshots. Changes to the tag list make automatic tags eligible for regeneration without losing manual additions/removals.
8. Use Vision OCR and image classification locally, then Apple Foundation Models to pick allowed tags and a short searchable title. If AI is unavailable, retain OCR search and manual tags and explain how to enable automatic tagging.
9. Keep originals in Photos, including iCloud Photos assets. Download from the user's iCloud Photos only as needed and only when enabled. Never upload screenshots or their contents to an AI service.
10. Handle denied/limited Photos access, missing local images, empty libraries, interrupted scans, model errors, and index persistence failures without deleting or silently resetting data.
11. Respect system light/dark mode by default; allow System, Light, Dark. Dark mode uses a true black background. Use native controls, neutral colors, and SF Symbols.
12. App icon: opaque black background, simple white screenshot symbol. No gradients, lettering, or colored accents.

## UI constraints
- One primary screen; a native floating Liquid Glass search circle expands on tap, with a live screenshot count and a single overflow menu.
- Hide secondary actions in menus or sheets; show batch actions only during selection.
- Minimal labels. Keep text only when it identifies an action, explains permission, or resolves an error.
- No onboarding carousel, welcome tour, upsell, chat UI, or settings for implementation details.
- Accessibility labels for icon buttons, scalable text, sufficient contrast, usable touch targets, and VoiceOver selection state.

## Engineering and delivery
- Complete Xcode project, app sources, assets, core tests, and short setup instructions. No third-party app dependencies or API keys.
- Persist the index atomically on-device; keep tag IDs stable across renames and remove dangling assignments when a tag is deleted.
- Bound image loading and inference work. Read and checkpoint searchable text before slower AI enrichment. Normally pause on backgrounding; allow an explicit, per-session request for OS-controlled background text indexing, with CPU-only Vision, real progress/cancellation, and foreground-only AI tags. Save progress incrementally and preserve successful OCR if tagging fails. Never imply an always-running background Photos watcher.
- Revalidate AI output against the current taxonomy. Treat screenshot text as data, never as instructions.
- Review the implementation against this file, then remove unnecessary UI. Record review results in REVIEW.md.
- Report verification honestly. Distinguish production compilation, native UI fixtures, real Photos/persistence behavior, local AI inference, and physical-device validation.

## Done means
Every requirement above is implemented or explicitly listed as a remaining limitation in REVIEW.md. Deliver the packaged project with clear instructions for opening it in Xcode and running on the user's iPhone.
