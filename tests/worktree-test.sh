#!/usr/bin/env bash

#
# Worktrees are classified by the same ladder as the branches they hold, and the
# dashboard counts what the plan would do.
#
# Both of those were untrue before: worktrees were sorted into "safe" and
# "candidates" while branches were sorted into merged and abandoned, and the
# dashboard counted merged pull requests while the plan counted merge evidence.
# A squash-merge repository saw a small number on one screen and a large one on
# the next, for the same branches.
#

set -u

# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gca-worktree.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
make_test_repository "$REPO"
load_assistant_into "$REPO"

git -C "$REPO" worktree add -q "$WORK/wt-squashed" squashed
git -C "$REPO" worktree add -q "$WORK/wt-unmerged" unmerged

refresh_worktree_list
scan_worktrees
scan_branches

echo "Worktree classification"

wt_id_of() {
    awk -F '\t' -v path="$1" '$2 == path { print $1; exit }' "$WORKTREE_DATA"
}

it "reads a worktree's merge state from the branch it holds"
assert_equals "PROVEN" "$(classify_worktree "$(wt_id_of "$WORK/wt-squashed")")"

it "leaves a worktree on unlanded work unclassified"
assert_equals "UNKNOWN" "$(classify_worktree "$(wt_id_of "$WORK/wt-unmerged")")"

it "never lists the primary worktree as a candidate"
assert_equals "" "$(wt_id_of "$REPO")"

#
# Uncommitted work outranks the evidence: the branch may well be merged, but
# what is at stake in the worktree is the change that is not.
#
echo "uncommitted" >> "$WORK/wt-squashed/file.txt"
scan_worktrees

it "holds a dirty worktree back even when its branch is merged"
assert_equals "PROVEN:DIRTY" "$(classify_worktree "$(wt_id_of "$WORK/wt-squashed")")"

it "reports that state in the scan as well"
assert_equals "DIRTY" "$(worktree_field "$(wt_id_of "$WORK/wt-squashed")" 6)"

echo
echo "Dashboard agrees with the plan"

# merged-by-ancestry and squashed; the second is the one no pull request could
# have told it about.
it "counts both routes to merged, including the squash"
assert_equals "2" "$(count_branch_class MERGED)"

it "counts the same branches the list labels MERGED"
assert_equals \
    "$(branch_display_rows | grep -c 'MERGED')" \
    "$(count_branch_class MERGED)"

it "counts the same worktrees the list labels MERGED"
assert_equals \
    "$(worktree_display_rows | grep -c 'MERGED')" \
    "$(count_worktree_class MERGED)"

#
# The dashboard's classes are exhaustive: a reader has to be able to add the
# column up and reach the total, which is only true if every class is printed.
#
it "prints every class it counts, so the dashboard adds up"
assert_contains "$(show_dashboard 2>/dev/null)" "Protected"

it "accounts for every branch in exactly one class"
assert_equals \
    "$(count_rows "$BRANCH_DATA")" \
    "$(( $(count_branch_class MERGED) \
       + $(count_branch_class ABANDONED) \
       + $(count_branch_class UNCLEAR) ))"

it "accounts for every worktree in exactly one class"
assert_equals \
    "$(count_rows "$WORKTREE_DATA")" \
    "$(( $(count_worktree_class MERGED) \
       + $(count_worktree_class ABANDONED) \
       + $(count_worktree_class UNCLEAR) ))"

summary
