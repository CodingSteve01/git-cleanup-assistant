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

## Releasing

`VERSION` in `bin/git-cleanup-assistant` is the single source of truth. Raise it in the
pull request that carries the change; merging to `main` publishes the tag, the GitHub
release with generated notes, and the Homebrew formula bump, in that order.

A merge that leaves `VERSION` alone releases nothing and ends quietly, so unreleased work
can accumulate on `main` as usual. The assistant reports its own version in its update
check, which is why the constant and the tag must agree: a stale constant would tell every
user that they are already up to date.

## Scope

This is a cleanup assistant for local worktrees and branches. Rewriting history, managing
remotes, or anything that touches commits is out of scope.
