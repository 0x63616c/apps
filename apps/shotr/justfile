default:
    @just --list

# Portable core and release-tool tests (no credentials or uploads).
test:
    swift test
    python3 -m unittest discover -s scripts/tests -v

# Full local validation, including isolated native UI tests and Release compilation.
verify:
    python3 scripts/release.py --verify

# Validate, sign, upload, wait for processing, and verify internal TestFlight availability.
release:
    python3 scripts/release.py

# Read back a previously uploaded build; never uploads another copy.
release-status build:
    python3 scripts/release.py --status {{build}}
