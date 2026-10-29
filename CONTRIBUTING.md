# Contributing

[Tickets](https://tickets.worldwidewebb.co) is the sole source of truth for work across Calum’s projects, replacing GitHub issues and Projects boards. This repository uses `APP` keys. Create and track work in Tickets; record dependencies with Tickets dependency edges.

Agents on the box start work with:

```sh
P=$(job new apps APP-12 short-slug)
source "$P/.job.env"
```

Use Conventional Commit PR titles ending with the ticket key, for example `feat(app): add thing [APP-12]`. Start the PR body with the linked ticket, `Closes [APP-12](https://tickets.worldwidewebb.co/t/APP-12)`, to close it on merge, or `Refs [APP-12](https://tickets.worldwidewebb.co/t/APP-12)` to link without closing. Include Summary, Changes and Testing. The PR conventions workflow checks the title key and that the body links the same ticket (it prints the exact line to add); bot PRs are exempt from the ticket key check.

UI PRs include screenshots made from synthetic fixture data, never real health data. For apps with `pr_screenshot_test` in `app.yml` (Tendr: `StillUITests/PRScreenshotTests`, using the `--demo --screenshots` fixture), the PR screenshots workflow captures the screens on the Mac runner and posts them as a PR comment; extend that test when a PR changes a screen it does not cover. Other apps attach simulator screenshots of the changed screens from their demo fixture by hand. Re-run with `gh workflow run pr-screenshots.yml -f app=<app> -f pr=<number>`.

Tickets links PRs through a GitHub webhook and moves tickets to In review when a PR opens and Done when it merges. Keep model labels on tickets: `model:astra` (`-m gpt-6-astra -c model_reasoning_effort=xhigh`) and `model:sol` (`-m gpt-6.1-sol`).

Read [AGENTS.md](AGENTS.md) for project conventions and [README.md](README.md) for the relevant checks. Keep changes focused and use synthetic fixtures; never commit credentials, signing assets or personal health data.
