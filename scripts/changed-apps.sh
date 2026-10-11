#!/usr/bin/env bash
# Prints a JSON array of the apps affected by changes between <base> and HEAD, for CI matrices.
#   scripts/changed-apps.sh <base-sha> [--build] [--only <app.yml key>]
# Shared code (packages/, fastlane/Fastfile, Gemfile*, the scripts CI runs) affects every app.
# With --build, changes that cannot alter an app binary (docs, listing text, README, screenshot
# frames) are ignored, so they never start a TestFlight upload. --only keeps apps whose app.yml sets
# that key (for example --only testflight). An unknown or empty base means every app.
set -euo pipefail
cd "$(dirname "$0")/.."

base=${1:-}
shift || true
build=false only=""
while (($#)); do
  case "$1" in
    --build) build=true ;;
    --only) only=${2:?--only needs a key}; shift ;;
    *) echo "Unknown option $1" >&2; exit 64 ;;
  esac
  shift
done

app_list=$(ruby scripts/app-config.rb --list ${only:+"$only"})
apps=()
while IFS= read -r app; do
  [[ -z "$app" ]] || apps+=("$app")
done <<< "$app_list"
json() { printf '%s\n' "$@" | ruby -rjson -e 'puts STDIN.read.split.uniq.to_json'; }
((${#apps[@]})) || { echo "[]"; exit 0; }

if [[ -z "$base" || "$base" =~ ^0+$ ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  json "${apps[@]}"; exit 0
fi
changed_files=$(git diff --no-renames --name-only "$base" HEAD)
files=()
while IFS= read -r file; do
  [[ -z "$file" ]] || files+=("$file")
done <<< "$changed_files"

shared='^(packages/|fastlane/Fastfile|fastlane/Appfile|Gemfile|scripts/(app-config\.rb|capture-screenshots\.sh|boot-simulator\.sh))'
$build || shared="$shared|^(scripts/|\.github/workflows/)"
ignored='^apps/[^/]+/(docs/|fastlane/|README\.md|screenshots\.json|AGENTS\.md)|\.md$'

affected=()
for file in "${files[@]}"; do
  if $build && [[ "$file" =~ $ignored ]]; then continue; fi
  if [[ "$file" =~ $shared ]]; then json "${apps[@]}"; exit 0; fi
  for app in "${apps[@]}"; do
    [[ "$file" == apps/"$app"/* ]] && affected+=("$app")
  done
done
((${#affected[@]})) && json "${affected[@]}" || echo "[]"
