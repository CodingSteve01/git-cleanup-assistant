#!/usr/bin/env bash

#
# The evidence ladder, checked against a repository that contains one of every
# case, with no forge involved. A squash-merged branch looking unmerged forever
# is the reason this tool exists, so it is the case worth pinning down.
#

set -u

# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# macOS resolves TMPDIR through a symlink, and git reports worktree paths
# resolved, so the expected paths in this file have to be resolved as well.
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gca-classification.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
make_test_repository "$REPO"
load_assistant_into "$REPO"

scan_worktrees
scan_branches

echo "Classification"

id_of() {
    awk -F '\t' -v branch="$1" '$2 == branch { print $1; exit }' "$BRANCH_DATA"
}

it "recognises a branch merged by ancestry"
assert_equals "PROVEN" "$(classify_branch "$(id_of merged-by-ancestry)")"

it "recognises a squash merge by patch equivalence"
assert_equals "PROVEN" "$(classify_branch "$(id_of squashed)")"

it "leaves work that never landed unclassified"
assert_equals "UNKNOWN" "$(classify_branch "$(id_of unmerged)")"

it "keeps the primary branch out of the scan entirely"
assert_equals "" "$(id_of main)"

it "reports the squash merge in the branch data, not just in the verdict"
assert_equals "true" "$(branch_field "$(id_of squashed)" 13)"

it "counts the commits an unmerged branch still carries"
assert_equals "1" "$(commits_not_on_base unmerged)"

#
# A branch checked out in a worktree is a candidate like any other, but the
# worktree has to go first, and the ladder has to say so.
#
git -C "$REPO" worktree add -q "$WORK/wt" unmerged
scan_worktrees
scan_branches

it "marks a branch that a worktree pins"
assert_equals "UNKNOWN:WT" "$(classify_branch "$(id_of unmerged)")"

it "names the worktree that pins it"
assert_equals "$WORK/wt" "$(branch_worktree_path unmerged)"

summary
