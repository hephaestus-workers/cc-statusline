# cc-statusline

A statusline for [Claude Code](https://claude.com/claude-code) that shows **which Claude account you are currently logged in with**, on top of the usual model / context / git / rate-limit info.

> Forked from [kamranahmedse/claude-statusline](https://github.com/kamranahmedse/claude-statusline) (MIT License).

```
Fable 5 │ 👤 yourname │ ✍️ 12% │ my-project (main) │ ⏱ 45m │ ● high

current ●●●○○○○○○○  31% ⟳ 6:00pm
weekly  ●●●●●○○○○○  52% ⟳ aug 3, 9:00am
```

## Install

```bash
npx @hephaestus-workers/cc-statusline
```

Then restart Claude Code.

## Uninstall

```bash
npx @hephaestus-workers/cc-statusline --uninstall
```

If a previous `~/.claude/statusline.sh` existed, it is restored from the backup taken at install time.

## Requirements

- `jq` (JSON parsing)
- `curl` (rate-limit fetch fallback)
- `git` (branch display)
- `bash` — on Windows this comes with [Git for Windows](https://gitforwindows.org/) (Git Bash), which Claude Code uses to run shell commands

Works on **Linux**, **Windows** (Git Bash), and macOS.

## Multi-account display

- The account segment (`👤 name`) reads `oauthAccount.emailAddress` from `~/.claude.json` and shows the part before `@`.
- If you separate accounts with the `CLAUDE_CONFIG_DIR` environment variable, the statusline reads `.claude.json`, `settings.json`, and credentials from that directory instead — so each account shows its own name and usage.
- If no account info is found, the segment is simply hidden; everything else still works.

## Differences from upstream

- **Account segment**: shows the currently logged-in Claude account (main feature of this fork).
- **`CLAUDE_CONFIG_DIR` aware**: settings, credentials, and usage cache follow the active config directory.
- **Token hygiene**: the OAuth token is passed to `curl` via stdin (`-H @-`) instead of a command-line argument, so it never appears in the process list (upstream [issue #29](https://github.com/kamranahmedse/claude-statusline/issues/29)).
- **Per-user cache**: usage cache moved from the shared `/tmp` to `~/.cache/cc-statusline/`, one file per config dir.
- **Windows/Linux first**: GNU `date`/`stat` variants are tried first (macOS BSD variants remain as fallback), and Windows-style paths (`C:\...`) are normalized before display.

## License

MIT — see [LICENSE](./LICENSE). Original work by [Kamran Ahmed](https://github.com/kamranahmedse); modifications by hephaestus-workers.
