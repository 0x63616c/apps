#!/usr/bin/env bash
# Publish site/ to the gh-pages branch (GitHub Pages, branch-based). Each app lives at
# site/<app>/ and is served at /<repo>/<app>/ (privacy at /<app>/privacy/, support at /<app>/support/).
#
# While site/.legacy-root names an app, that app is also mirrored at the site root. This keeps
# Tendr's original URLs (https://0x63616c.github.io/tendr/, /privacy/, /support/) working until the
# repository is renamed; see docs/RENAME.md. Only site/ is published, so planning docs stay private.
# Uses [skip ci] so the push does not start CI or TestFlight.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
src="$(git -C "$root" rev-parse --short HEAD)"
tmp="$(mktemp -d)"
trap 'git -C "$root" worktree remove --force "$tmp" >/dev/null 2>&1 || true' EXIT
git -C "$root" fetch -q origin "+refs/heads/gh-pages:refs/remotes/origin/gh-pages" 2>/dev/null || true
if git -C "$root" show-ref -q --verify refs/remotes/origin/gh-pages; then
  git -C "$root" worktree add -q -B gh-pages "$tmp" origin/gh-pages
else
  git -C "$root" worktree add -q --detach "$tmp"
  git -C "$tmp" checkout -q --orphan gh-pages
fi
git -C "$tmp" rm -rqf . >/dev/null 2>&1 || true
# Worktrees contain a .git file; assemble separately so the preview builder requires an empty directory.
staging=$(mktemp -d)
trap 'rm -rf "$staging"; git -C "$root" worktree remove --force "$tmp" >/dev/null 2>&1 || true' EXIT
"$root/scripts/build-site.sh" "$staging"
cp -R "$staging/." "$tmp/"
git -C "$tmp" add -A
if git -C "$tmp" diff --cached --quiet; then echo "gh-pages already up to date"; exit 0; fi
git -C "$tmp" commit -q -m "Publish site from ${src} [skip ci]"
git -C "$tmp" push -q origin gh-pages
echo "Published site from ${src} to gh-pages"
