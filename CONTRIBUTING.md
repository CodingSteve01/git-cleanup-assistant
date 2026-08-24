# Contributing

Bug reports and small, focused pull requests are welcome.

## Before you open a pull request

- `bash -n bin/git-cleanup-assistant` must pass
- `shellcheck bin/git-cleanup-assistant` should not gain new warnings
- Try the change against a scratch repository with a few worktrees and stale branches

## Ground rules

- The safety rules in the README are the contract. A change that can delete a dirty
  worktree, a checked-out branch, or an unmerged branch without an explicit confirmation
  will not be merged.
- No new runtime dependencies beyond `git`, `gum` and `gh`.
- Portable shell only. The script runs under `bash` with `set -u`; keep it working with
  the `awk` and `date` that macOS ships, which are not the GNU versions. In particular,
  `awk` there rejects a line break directly after an opening parenthesis.
- Match the existing style: four-space indent, section banners, functions that do one thing.

## Scope

This is a cleanup assistant for local worktrees and branches. Rewriting history, managing
remotes, or anything that touches commits is out of scope.
