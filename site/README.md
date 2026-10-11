# Site

One GitHub Pages site for every -r app. Each app has its own folder with a home page, privacy policy and support page:

- `site/<app>/` → `https://0x63616c.github.io/<repo>/<app>/`
- `site/<app>/privacy/` and `site/<app>/support/` → the URLs in that app's App Store listing

Plain HTML and CSS in the RDesign palette (black, white and graphite; card radius 24). Light and dark follow `prefers-color-scheme`. `scripts/new-app.sh` adds a folder from `templates/new-app/site/` and a card to `site/index.html`.

Edit files here, then run `scripts/publish-site.sh` to copy `site/` to the `gh-pages` branch.

`site/.legacy-root` mirrors one app at the site root. It keeps Tendr's original URLs (`/tendr/`, `/tendr/privacy/`, `/tendr/support/`) working while this repository is still called `tendr`. Remove it as part of the rename in `docs/RENAME.md`.

Preview without publishing: `scripts/build-site.sh /tmp/apps-pages-preview` (empty output directory). `scripts/publish-site.sh` pushes only when explicitly run; it was not run during the monorepo migration.
