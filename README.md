# git-cleanup-assistant

An interactive terminal assistant for cleaning up local Git worktrees and branches.

Repositories that see a lot of feature work accumulate leftovers: worktrees whose pull
request was merged months ago, local branches whose upstream is gone, branches that were
squash-merged and therefore look unmerged to `git branch --merged`. This tool lists those
leftovers, tells you why each one is a candidate, and lets you remove them in bulk without
losing work you still need.

## What it does

- Lists worktrees and local branches with age, state, upstream status and pull request status
- Detects squash merges from git alone, by patch id, with no forge involved
- Detects merged pull requests through the GitHub API when `gh` is available
- Multi-select with fuzzy search, so you can pick 20 branches in one pass
- One action cleans up the whole repository: an evidence ladder decides per branch, a plan
  says what will happen, one confirmation carries it out
- Clears the worktree that pins a branch as part of deleting it, instead of sending you to
  another menu
- Bulk force deletion for branches Git will never call merged, gated behind an evidence table
- Guided cleanup that goes straight for the obvious candidates
- Caches pull request metadata once per run instead of querying per branch
- Checks once a day whether a newer release exists and can upgrade itself via Homebrew

## How deleting works

**Clean up now** takes every local branch, no list to work through first, and shows the
plan before it touches anything:

```
Deletion Plan

 27 merged
      already on origin/main: by ancestry, by patch after a squash
      merge, or by a merged pull request

 22 abandoned
      the remote branch was deleted and no pull request is open

  5 unclear
      no signal either way; confirmed separately

  4 of these need a worktree removed first, confirmed one by one
```

One confirmation covers everything with evidence behind it. Only **unclear** is held back
behind an evidence table and a typed `DELETE`. Any worktree in the way is confirmed on its
own before it is removed, and every deleted branch prints the command that brings it back.

Each branch is placed by an evidence ladder, strongest rung first:

| Rung | Means | Source |
|---|---|---|
| **merged** | the tip is an ancestor of the base ref | git |
| **merged** | rolled into one commit, its patch is already on the base ref | git |
| **merged** | a merged pull request | forge |
| **abandoned** | the remote branch was deleted and no pull request is open | git, refined by forge |
| **unclear** | none of the above | — |

The second rung is what makes a squash-merge repository workable: a squash replaces the
branch's commits, so the tip is never an ancestor and `git branch -d` refuses it forever.
Comparing patch ids finds the work anyway.

The **abandoned** rung is not proof that the work landed. Deleting the remote branch is a
deliberate act by whoever deleted it, and carrying out that decision is what this tool is
for — which is why it needs one confirmation rather than a typed `DELETE`.

Prefer picking branches by hand? **Local branches** opens the same list with the same
classes; typing `MERGED`, `ABANDONED`, `UNCLEAR` or `IN-WT` narrows it, and **Delete
selected** runs the same plan over your selection.

## Safety rules

The whole point is that a bulk delete stays boring. These rules are enforced in code:

- The primary worktree and its branch are never removed
- Dirty worktrees are never bulk deleted; removing one needs a typed `DELETE` confirmation
- A branch checked out in a worktree is never deleted behind your back; the assistant
  offers to remove the worktree first and confirms that removal separately
- A worktree is only removed when the branch deletion behind it will actually go through,
  so uncommitted work is never discarded for a deletion that then fails
- Nothing is deleted before the plan has been shown and confirmed
- A deleted branch is always recoverable: forced deletion drops the label, not the
  commits, and the hash is printed with the command that restores it
- **Changed in 0.3.0:** a `gone` upstream with no open pull request is now enough to
  delete a branch under the plan's single confirmation. It used to require a typed
  `DELETE`. Deleting the remote branch is a deliberate act, the local commits survive in
  the reflog, and the old rule meant a repository full of finished work could not be
  cleaned up without confirming it 25 times. A branch with no signal at all still needs
  the typed `DELETE`.
- Every refusal and every skipped branch is reported with Git's own reason, so a run that
  deletes nothing says why
- Deleting an *unclear* branch needs a typed `DELETE` on top of the plan's confirmation

## Does it need GitHub?

No. `gh` is optional and every rung that clears a branch on its own comes from git:
ancestry, patch equivalence after a squash merge, and whether the upstream is gone. A run
with no `gh` installed classifies the same branches the same way — the bundled tests cover
exactly that case.

What a forge adds is whether a pull request is still **open**, which keeps a branch out of
*abandoned* while its review is alive, and a merged pull request as a third route to
*merged*. Useful, not required.

Only GitHub is wired up today, in `refresh_pr_cache` and `pr_info_for_branch`. Those two
functions are the whole seam; a GitLab or Gitea equivalent replaces them and nothing else.

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

Releases are cut by release-please from the Conventional Commit subjects on `main`:
merging its release pull request publishes the tag, the release and the Homebrew formula
bump. See [CONTRIBUTING.md](CONTRIBUTING.md).

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
