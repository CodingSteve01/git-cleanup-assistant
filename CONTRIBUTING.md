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
- No new runtime dependencies beyond `git`, `gum` and `gh`. `gh` is optional and must stay
  that way: a rung of the evidence ladder that only a forge can answer may refine a
  classification, never be the only thing that produces one.
- Portable shell only. The script runs under `bash` with `set -u`; keep it working with
  the `awk` and `date` that macOS ships, which are not the GNU versions. In particular,
  `awk` there rejects a line break directly after an opening parenthesis.
- Match the existing style: four-space indent, section banners, functions that do one thing.

## Commit and pull request titles

Titles follow [Conventional Commits](https://www.conventionalcommits.org). The repository
squash-merges, so the pull request title becomes the commit subject on `main`, and that
subject is the only thing release-please reads:

```
fix: ...       patch release
feat: ...      minor release
feat!: ...     major release, as does a "BREAKING CHANGE:" body
docs: ...      no release
chore: ...     no release
```

A scope is optional (`fix(worktree): ...`). Titles and commits are both checked by
[commitlint](https://commitlint.js.org) against `commitlint.config.cjs` in the *Commit
lint* workflow, because a title that does not parse would otherwise produce no release at
all rather than an error.

The body and footer line-length rules are off: squash merges discard the body, so the rule
only ever rejected text that never reaches `main`.

## Releasing

Nobody picks version numbers. release-please keeps a release pull request open with the
next version and the changelog derived from the commit subjects since the last tag.
Merging that pull request publishes the tag and the GitHub release, and the same workflow
then bumps the Homebrew formula.

`VERSION` in `bin/git-cleanup-assistant`, `version.txt` and
`.release-please-manifest.json` are all written by release-please. Do not edit them by
hand; the `# x-release-please-version` annotation on the `VERSION` line is what lets it
rewrite the constant, and the release job fails if the constant and the tag ever disagree.

## Scope

This is a cleanup assistant for local worktrees and branches. Rewriting history, managing
remotes, or anything that touches commits is out of scope.
