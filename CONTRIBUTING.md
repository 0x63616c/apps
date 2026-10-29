# Contributing

[Tickets](https://tickets.worldwidewebb.co) is the sole source of truth for work across Calum’s projects, replacing GitHub issues and Projects boards. This repository uses `APP` keys. Create and track work in Tickets; record dependencies with Tickets dependency edges.

Agents on the box start work with:

```sh
P=$(job new apps APP-12 short-slug)
source "$P/.job.env"
```

Use Conventional Commit PR titles ending with the ticket key, for example `feat(app): add thing [APP-12]`. Start the PR body with `Closes APP-12` to close the ticket on merge, or `Refs APP-12` to link without closing. Include Summary, Changes and Testing. The PR conventions workflow checks titles; bot PRs are exempt from the ticket key check.

Tickets links PRs through a GitHub webhook and moves tickets to In review when a PR opens and Done when it merges. Keep model labels on tickets: `model:astra` (`-m gpt-6-astra -c model_reasoning_effort=xhigh`) and `model:sol` (`-m gpt-6.1-sol`).

Read [AGENTS.md](AGENTS.md) for project conventions and [README.md](README.md) for the relevant checks. Keep changes focused and use synthetic fixtures; never commit credentials, signing assets or personal health data.
