# cc-statusline

A statusline for [Claude Code](https://claude.com/claude-code) that shows **which Claude account you are currently logged in with**, on top of the usual model / context / git / rate-limit info.

> Forked from [kamranahmedse/claude-statusline](https://github.com/kamranahmedse/claude-statusline) (MIT License).

```
Fable 5 │ 👤 yourname │ ✍️ 12% │ my-project (main) │ ⏱ 45m │ ● high

current ●●●○○○○○○○  31% ⟳ 6:00pm
weekly  ●●●●●○○○○○  52% ⟳ aug 3, 9:00am
fable   ●○○○○○○○○○   9% ⟳ aug 3, 9:00am
```

## Install

```bash
npx @hephaestus-workers/cc-statusline
```

Then restart Claude Code.

## Update

From v1.2.0 the statusline **keeps itself up to date**. About once a day it asks the npm registry
for the latest version in the background, and if there is a newer one it re-runs the installer. It
only ever moves forward — an install ahead of the registry is left alone — and the check runs
detached from rendering, so it never delays the statusline. The new file is swapped in with
`rename()`, so a statusline run already in flight finishes against the copy it started with.

To turn it off, set `CC_STATUSLINE_NO_SELF_UPDATE=1` in your environment.

Upgrading keeps the backup taken at first install, so `--uninstall` still restores whatever
statusline you had before cc-statusline. If you had none, no backup is kept and `--uninstall`
simply removes it.

Two cases still need a manual run:

```bash
npx @hephaestus-workers/cc-statusline@latest
```

- **Coming from v1.1.0 or earlier**, which has no self-update code — one manual run bootstraps it.
- **You want the update now** rather than within a day.

The `@latest` matters: without it `npx` may reuse an older copy from its own cache.

## Uninstall

```bash
npx @hephaestus-workers/cc-statusline --uninstall
```

If a statusline of your own was there before cc-statusline, it is restored from the backup taken at
install time. Otherwise the script is removed and the `statusLine` key is dropped from
`~/.claude/settings.json`, leaving your other settings untouched.

## Requirements

- `jq` (JSON parsing)
- `curl` (usage API fetch)
- `git` (branch display)
- `bash` — on Windows this comes with [Git for Windows](https://gitforwindows.org/) (Git Bash), which Claude Code uses to run shell commands

Works on **Linux**, **Windows** (Git Bash), and macOS.

## Multi-account display

- The account segment (`👤 name`) reads `oauthAccount.emailAddress` from `~/.claude.json` and shows the part before `@`.
- If you separate accounts with the `CLAUDE_CONFIG_DIR` environment variable, the statusline reads `.claude.json`, `settings.json`, and credentials from that directory instead — so each account shows its own name and usage.
- If no account info is found, the segment is simply hidden; everything else still works.

## Per-model weekly limits

Under `weekly` the statusline also shows any **model-scoped** weekly limit your plan has, such as
the separate Fable allowance:

```
weekly  ●●●●●○○○○○  52% ⟳ aug 3, 9:00am
fable   ●○○○○○○○○○   9% ⟳ aug 3, 9:00am
```

Claude Code's statusline input only carries the overall `five_hour` and `seven_day` windows, so this
line comes from the same OAuth usage endpoint the rest of the rate-limit fallback already uses. The
label is whatever the API calls the scoped model, so a renamed or additional one appears on its own.
If your plan has no model-scoped limit, no extra line is drawn.

Keeping that line current means the usage snapshot is refreshed about once a minute even when Claude
Code already supplies rate limits on stdin. The refresh runs in the background and the statusline
renders from the cached snapshot, so it never waits on the network. A failed fetch backs off for five
minutes rather than retrying on every render.

## Differences from upstream

- **Account segment**: shows the currently logged-in Claude account (main feature of this fork).
- **Per-model weekly limits**: a line under `weekly` for model-scoped allowances such as Fable.
- **Self-updating**: a daily background check keeps the installed copy current (`CC_STATUSLINE_NO_SELF_UPDATE=1` opts out).
- **`CLAUDE_CONFIG_DIR` aware**: settings, credentials, and usage cache follow the active config directory.
- **Token hygiene**: the OAuth token is passed to `curl` via stdin (`-H @-`) instead of a command-line argument, so it never appears in the process list (upstream [issue #29](https://github.com/kamranahmedse/claude-statusline/issues/29)).
- **Per-user cache**: usage cache moved from the shared `/tmp` to `~/.cache/cc-statusline/`, one file per config dir.
- **Non-blocking refresh**: the usage snapshot is fetched in the background behind a lock, so a slow network never delays a render and Claude Code's cancellation of a long-running statusline can't stall the refresh.
- **Windows/Linux first**: GNU `date`/`stat` variants are tried first (macOS BSD variants remain as fallback), and Windows-style paths (`C:\...`) are normalized before display.

## License

MIT — see [LICENSE](./LICENSE). Original work by [Kamran Ahmed](https://github.com/kamranahmedse); modifications by hephaestus-workers.
