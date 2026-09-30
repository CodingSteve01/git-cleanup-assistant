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
- One action cleans up the whole repository — worktrees and branches: an evidence ladder
  decides per item, a plan says what will happen, one confirmation carries it out
- Candidates start selected, so a cleanup is deselecting what you want to keep rather than
  Tab-selecting twenty entries out of a filter
- Never touches a protected branch, whatever the evidence says
- Clears the worktree that pins a branch as part of deleting it, instead of sending you to
  another menu
- Bulk force deletion for branches Git will never call merged, gated behind an evidence table
- Asks the forge only about the branches that exist locally, so startup does not scale with
  the repository's pull request history
- Checks once a day whether a newer release exists and can upgrade itself via Homebrew
- Runs unattended as well: `--plan` prints the plan and changes nothing, `--apply-merged`
  removes only clean worktrees whose work is provably merged, for a timer or a cron job

## How deleting works

**Clean up everything** takes every worktree and every local branch, no list to work
through first, and shows the plan before it touches anything. Worktrees go first, because
removing one is what frees the branch underneath it:

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

Worktrees are classified by the same ladder, reading the merge evidence of the branch they
hold, and removed through a plan of the same shape. Dirty and locked worktrees are carried
as a state rather than a class: they are never removed in bulk, whatever the evidence says
about the branch, and are reviewed one at a time.

One confirmation covers everything with evidence behind it. Only **unclear** is held back
behind an evidence table and a typed `DELETE`. Any worktree in the way is confirmed on its
own before it is removed, and every deleted branch prints the command that brings it back.

Each branch is placed by an evidence ladder, strongest rung first:

| Rung | Means | Source |
|---|---|---|
| **protected** | the branch outlives the work merged out of it | configuration |
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

Prefer picking things by hand? **Local branches** and **Worktrees** open the same lists
with the same classes; typing `MERGED`, `ABANDONED`, `UNCLEAR`, `PROTECTED` or `IN-WT`
narrows them, and the delete and remove actions run the same plans over your selection.

## Protected branches

A release branch is merged into the base ref and then carries on being a release branch.
Every rung of the ladder reports it as finished and every one of them is right — the
conclusion is what is wrong. Protected branches sit above the whole ladder: labelled as
such in both lists, never pre-selected, listed under *kept* in the plan, and refused by the
deletion itself.

The default covers `main`, `master`, `develop`, `development`, `staging`, `production`,
`release/*` and `support/*`. It is a default, not a policy — the answer belongs to the
repository:

```sh
git config cleanup-assistant.protected '^(main|release/.*|integration)$'
```

`GIT_CLEANUP_ASSISTANT_PROTECTED` overrides that for a single run.

## You always know what you are acting on

A cleanup tool that cannot say *which* worktree it is about to empty is a worse tool than
no cleanup tool. Three rules therefore hold at every prompt, and there are tests that fail
when one of them is broken:

- **The header names its subject.** Not "What should happen to this worktree?" but
  `fix/NA-1164/fehlerkatalog (3 of 7) — 402 changes: 400 deleted, 2 untracked. What should
  happen?` A review that stops seven times says which stop this is.
- **A list is previewed, never dumped.** The first lines are shown, the rest is counted,
  and the preview shrinks to whatever the terminal can hold — a bounded list that does not
  fit would still push the subject off the top of the screen, which is the failure this
  replaces.
- **The full list is one entry away.** Every group confirmation offers `Show all 402 first`
  and re-asks the question when the pager closes, so nothing has to be answered from a
  count alone.

A screen before an irreversible step therefore looks like this:

```
════════════════════════════════════════════════════════════
fix/NA-1164/fehlerkatalog (3 of 7)
════════════════════════════════════════════════════════════
Worktree:    ~/worktrees/voffice/fehlerkatalog
Branch:      fix/NA-1164/fehlerkatalog
Last commit: 2026-09-11 (7 days ago)
Evidence:    PROVEN — the branch is already on main
State:       DIRTY — 402 changes: 400 deleted, 2 untracked

     D Vo.Tests.Disposition.Integration/Tours/TourCheckerTests.cs
     D Vo.Tests.Disposition.Integration/Tours/TourGeneratorTests.cs
    … and 400 more

  fix/NA-1164/fehlerkatalog (3 of 7) — 402 changes: 400 deleted, 2 untracked.
  What should happen?
    Keep this worktree and move on
    Show all 402 changes
    Show recent commits
    Remove worktree and DISCARD 402 change(s)
    Stop reviewing the rest
```

The same applies to the plans: every group names its members instead of only counting
them, so `Remove these 12 worktrees` is answered with the twelve names on screen.

## Safety rules

The whole point is that a bulk delete stays boring. These rules are enforced in code:

- Every prompt names what it acts on, and every list it shows can be read to the end
- The primary worktree and its branch are never removed
- A protected branch is never deleted, and neither is the worktree that holds it
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
- A typed confirmation repeats what it destroys: `Type DELETE to discard 402 change(s) in
  'fix/NA-1164/fehlerkatalog':`, never a bare `Type DELETE to confirm:`
- A cancelled prompt always means *no*, including the `Esc` that closes a menu

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

On startup it asks for one thing, the **base ref** that merge checks are measured against,
and only when there is more than one sensible answer. Candidates are the refs that actually
exist, best first: the remote's own default branch via `origin/HEAD`, then the primary
branch, then the usual names. Nothing else is asked before you have seen the repository.

A few knobs live in the environment rather than in a prompt:

| Variable | Default | Effect |
|---|---|---|
| `GIT_CLEANUP_ASSISTANT_BASE_REF` | chosen | the ref merge state is measured against |
| `GIT_CLEANUP_ASSISTANT_PROTECTED` | see above | branches never offered for deletion |
| `GIT_CLEANUP_ASSISTANT_STALE_DAYS` | `30` | the age reported on the dashboard |
| `GIT_CLEANUP_ASSISTANT_NO_UPDATE_CHECK` | unset | set to `1` to skip the update check |
| `GIT_CLEANUP_ASSISTANT_IGNORE_DIRTY` | unset | paths whose changes do not make a worktree dirty, see below |
| `GIT_CLEANUP_ASSISTANT_MIN_IDLE_DAYS` | `7` | quiet period for `--apply-merged`, see below |
| `GIT_CLEANUP_ASSISTANT_PREVIEW_LIMIT` | `12` | lines per group in `--plan` and `--apply-merged` output |

## Unattended runs

Two flags run the assistant without gum, without a single prompt and without the update
check, so it can run from a timer on a machine nobody is looking at:

```sh
git fetch --prune
git-cleanup-assistant --plan
git-cleanup-assistant --apply-merged --base-ref origin/main
```

| Flag | Effect |
|---|---|
| `--plan` | prints the plan **Clean up everything** would show, worktrees and branches, and changes nothing. Exit 0 |
| `--apply-merged` | removes the worktrees of the plan's *merged* group and nothing else; everything it keeps is listed with the reason |
| `--delete-branches` | with `--apply-merged` only: also deletes merged local branches that no worktree holds any more. Off by default |
| `--base-ref REF` | measures merge state against `REF`; wins over `GIT_CLEANUP_ASSISTANT_BASE_REF`. Without either, the best candidate is taken |
| `--min-idle-days N` | leaves merged worktrees alone whose `HEAD` moved in the last `N` days. Default `7`, `0` turns it off |
| `-h`, `--help` | usage |
| `--version` | prints the version |

`--apply-merged` removes a worktree only when all of this holds:

- its branch, or its detached `HEAD`, has merge evidence: ancestry, patch equivalence after
  a squash merge, or a merged pull request found through `gh`
- it is clean, checked again right before the removal
- it is not the primary worktree, not locked, and does not hold a protected branch
- its `HEAD` has not moved for `--min-idle-days` days, read from the worktree's reflog

The last rule exists because a worktree created a minute ago for work that has not started
yet sits on the base ref: ancestry calls it merged, and it is clean. Both are true, and the
removal would still pull it out from under whoever just created it. The quiet period is
also read from `GIT_CLEANUP_ASSISTANT_MIN_IDLE_DAYS` or `git config
cleanup-assistant.min-idle-days`, the flag winning over both.

*Unclear* and *abandoned* stay, because both need a decision and there is nobody to make
it; so do dirty and locked worktrees. Neither mode fetches: run `git fetch --prune` first,
or the base ref is as old as the last fetch. A base ref that does not exist stops the run
before anything is changed.

Every removal is one line with the path, the evidence and the command that brings the
worktree back:

```
✓ Removed worktree /data/wt/login-timeout  ·  fix/login-timeout is on origin/main as a squash-merged patch  ·  restore: git worktree add /data/wt/login-timeout fix/login-timeout
```

A detached worktree is restored from its commit with `git worktree add --detach`. The
exit code is 1 when a removal git refused, 2 for a usage error, 0 otherwise.

Detached worktrees go through the same ladder. Their commit is checked for ancestry and
patch equivalence against the base ref, and when git finds nothing, `gh` is asked which
pull request contains that commit.

### Changes that do not count

Some tooling changes every worktree it runs in, for example a test run that moves a
submodule pointer. Every such worktree then reads as dirty and is never removed. Paths
listed here are left out of the dirty check, the path itself and everything below it:

```sh
git config cleanup-assistant.ignore-dirty api-contracts
git config --add cleanup-assistant.ignore-dirty generated/contracts
```

Commas or spaces separate several paths in one value, and
`GIT_CLEANUP_ASSISTANT_IGNORE_DIRTY` overrides the configuration for one run. Nothing is
ignored unless configured. The setting applies to the interactive assistant as well, so
both describe a worktree the same way.

## Large repositories

Startup used to list the repository's entire pull request history, one request per hundred
entries. With 2500 pull requests and 70 local branches that is 26 requests spent learning
about 2430 branches that are not on the machine, paid again on every refresh — the cost
scaled with the repository's age rather than with anything the user could see.

It now asks about the branches that exist locally, up to fifty per GraphQL request, so a
normal repository is one round trip. Scanning was reworked the same way: worktree metadata
comes from one `git for-each-ref` instead of three git processes per worktree, the porcelain
worktree list is read once per scan instead of once per lookup, `git status` runs a few
worktrees at a time, and menus only rescan when something actually changed.

Measured on a repository with 36 worktrees, 71 branches and 2500 pull requests:

| | before | after |
|---|---|---|
| Pull request metadata | 17.4s | 2.1s |
| Repository scan | 71s | 11s |
| Scan per menu pass | every time | only after a change |

## Tests

```sh
bash tests/run.sh
```

The suites build their own scratch repositories and never reach a forge, so the no-`gh`
path is what they exercise by default. CI runs them under Bash 3.2 as well, which is what
macOS ships and therefore what most people run this with.

They cover the logic, not the terminal. The interactive flow was verified separately by
driving a real run through a pseudo terminal against a scratch repository — which is how two
failures were found that no unit test would have reached: `gum input` panicking on an empty
field, and an unresolvable base ref silently reporting every branch as unclear.

What a screen says is testable, though, and `tests/disclosure-test.sh` tests it: the
change summaries, the bounded previews and their fit to the terminal, the subject and its
position, and a confirmation that offers the full list and treats a cancelled menu as a
no. Four of its cases are structural — they grep the script for the anonymous prompts that
used to be there (`What should happen to this worktree?`, `Type DELETE to confirm`, an
unbounded `status --short`) so that reintroducing one fails here rather than in front of
someone with four hundred changed files on screen.

## Requirements

- Git 2.22 or newer (`git branch --show-current`)
- [gum](https://github.com/charmbracelet/gum) for the interactive prompts; `--plan` and
  `--apply-merged` do not need it
- [GitHub CLI](https://cli.github.com) for pull request detection, authenticated via `gh auth login`

On macOS the script offers to install both through Homebrew on first run. On other systems
install them yourself; everything else the script uses is Git plus standard POSIX tools.

## License

MIT, see [LICENSE](LICENSE).
