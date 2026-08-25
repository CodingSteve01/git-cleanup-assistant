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
- Guided cleanup that goes straight for the obvious candidates
- Caches pull request metadata once per run instead of querying per branch
- Bulk force deletion for branches Git will never call merged, gated behind an evidence table
- Checks once a day whether a newer release exists and can upgrade itself via Homebrew

## Safety rules

The whole point is that a bulk delete stays boring. These rules are enforced in code:

- The primary worktree and its branch are never removed
- Dirty worktrees are never bulk deleted; removing one needs a typed `DELETE` confirmation
- Checked-out branches are never deleted
- A `gone` upstream alone never triggers a forced branch deletion
- Forced deletion is offered automatically only when GitHub confirms the pull request was merged
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
