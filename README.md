# git-cleanup-assistant

An interactive terminal assistant for cleaning up local Git worktrees and branches.

Repositories that see a lot of feature work accumulate leftovers: worktrees whose pull
request was merged months ago, local branches whose upstream is gone, branches that were
squash-merged and therefore look unmerged to `git branch --merged`. This tool lists those
leftovers, tells you why each one is a candidate, and lets you remove them in bulk without
losing work you still need.

## What it does

- Lists worktrees and local branches with age, state, upstream status and pull request status
- Detects merged pull requests through the GitHub API, including squash merges
- Multi-select with fuzzy search, so you can pick 20 branches in one pass
- One delete action that works out per branch what applies, instead of asking you to pick
  a strategy for a mixed selection
- Clears the worktree that pins a branch as part of deleting it, instead of sending you to
  another menu
- Bulk force deletion for branches Git will never call merged, gated behind an evidence table
- Guided cleanup that goes straight for the obvious candidates
- Caches pull request metadata once per run instead of querying per branch
- Checks once a day whether a newer release exists and can upgrade itself via Homebrew

## How deleting works

Pick branches from one list; typing filters it, so `GONE`, `MERGED`, `GIT` and `IN-WT`
narrow it down without a separate menu. Then choose **Delete selected** once. The
assistant sorts the selection itself and shows the plan before it touches anything:

```
Deletion Plan

  6 delete
      merged into origin/main, confirmed by a merged pull request,
      or accepted by Git itself
      2 of them need a worktree removed first

  3 force delete
      nothing proves these are merged; confirmed separately

  1 keep
      checked out in the primary worktree, which always stays
```

Deletions Git or GitHub can vouch for run straight through. The rest is held back behind
an evidence table and a typed `DELETE`, and any worktree in the way is confirmed on its
own before it is removed.

This replaces the earlier flow, which asked for a cleanup mode before showing anything and
then for a deletion strategy. Both questions came too early: the modes overlap, so there
was no right one to pick, and a mixed selection has no single right strategy — whichever
one you chose silently dropped the branches it did not cover.

## Safety rules

The whole point is that a bulk delete stays boring. These rules are enforced in code:

- The primary worktree and its branch are never removed
- Dirty worktrees are never bulk deleted; removing one needs a typed `DELETE` confirmation
- A branch checked out in a worktree is never deleted behind your back; the assistant
  offers to remove the worktree first and confirms that removal separately
- A worktree is only removed when the branch deletion behind it will actually go through,
  so uncommitted work is never discarded for a deletion that then fails
- A `gone` upstream alone never triggers a forced branch deletion
- A branch is deleted without a further question only when its merge is proven: reachable
  from the base ref, confirmed by a merged pull request, or accepted by `git branch -d`
- Every refusal and every skipped branch is reported with Git's own reason, so a run that
  deletes nothing says why
- Forcing a deletion in bulk needs a typed `DELETE` confirmation and prints the commit hash
  of each deleted branch, so any of them can be restored with `git branch <name> <hash>`

Without GitHub authentication the tool still works, it just falls back to what Git alone
knows about merges.

### Safe deletion in a squash-merge repository

`git branch -d` calls a branch merged only when its commits are reachable from `HEAD`. A
squash merge rewrites those commits, so every squash-merged branch stays "not fully merged"
forever and safe deletion clears none of them. Two things follow:

- Merge state is measured against the base ref you enter at startup, not against whatever
  `HEAD` happens to be. Running the assistant from a worktree that sits on a feature branch
  no longer makes Git refuse branches that were merged long ago.
- Branches that a squash merge left behind are cleared through **Force delete selected
  branches**, which shows the pull request state, the `gone` flag and the number of commits
  that are not on the base ref for each branch before anything is deleted.

## Updates

Once a day, on startup, the assistant compares its own version against the latest
GitHub release. When a newer one exists and the copy is managed by Homebrew, it offers
the upgrade and restarts itself into the new version; otherwise it prints the release
link and carries on. A missing network, a rate-limited API or no release at all leaves
the session untouched.

Set `GIT_CLEANUP_ASSISTANT_NO_UPDATE_CHECK=1` to switch the check off. The timestamp of
the last check lives in `${XDG_CACHE_HOME:-~/.cache}/git-cleanup-assistant/`.

Releases are cut from the `VERSION` constant in the script: raising it and merging to
`main` publishes the tag, the release and the Homebrew formula bump. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## Install

Via Homebrew:

```sh
brew install CodingSteve01/tap/git-cleanup-assistant
```

Manually:

```sh
git clone https://github.com/CodingSteve01/git-cleanup-assistant.git
install -m 755 git-cleanup-assistant/bin/git-cleanup-assistant /usr/local/bin/
```

## Usage

Run it inside the repository you want to clean up:

```sh
git-cleanup-assistant
```

Because the file is named `git-*` and lives on your `PATH`, Git picks it up as a subcommand
as well:

```sh
git cleanup-assistant
```

On startup it asks for two settings:

- **Stale threshold** in days, default `30` — how long a branch may sit without commits
  before it shows up as a candidate
- **Base ref** for merge checks, default `origin/main`

## Requirements

- Git 2.22 or newer (`git branch --show-current`)
- [gum](https://github.com/charmbracelet/gum) for the interactive prompts
- [GitHub CLI](https://cli.github.com) for pull request detection, authenticated via `gh auth login`

On macOS the script offers to install both through Homebrew on first run. On other systems
install them yourself; everything else the script uses is Git plus standard POSIX tools.

## License

MIT, see [LICENSE](LICENSE).
