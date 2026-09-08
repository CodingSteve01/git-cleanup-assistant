#!/usr/bin/env bash

#
# A release branch is merged into main and then carries on being a release
# branch. Every rung of the evidence ladder reports it as finished, and every one
# of them is right — the conclusion is what is wrong.
#
# This matters more since candidates start selected: a list that pre-selects
# everything it believes is merged must not believe that about a branch the team
# still ships from.
#

set -u

# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gca-protected.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
make_test_repository "$REPO"

#
# A release branch that really is merged into the base ref: the hardest case,
# because nothing in git says to keep it.
#
git -C "$REPO" checkout -qb release/6.25
echo release >> "$REPO/file.txt"
git -C "$REPO" commit -qam "release work"
git -C "$REPO" checkout -q main
git -C "$REPO" merge -q --no-ff -m "merge release" release/6.25

load_assistant_into "$REPO"
resolve_protected_pattern
refresh_worktree_list
scan_worktrees
scan_branches

echo "Protected branches"

id_of() {
    awk -F '\t' -v branch="$1" '$2 == branch { print $1; exit }' "$BRANCH_DATA"
}

it "uses the built-in pattern when nothing is configured"
assert_equals "$DEFAULT_PROTECTED_PATTERN" "$PROTECTED_PATTERN"

it "recognises a release branch"
assert_equals "0" "$(branch_is_protected release/6.25 && echo 0 || echo 1)"

it "does not protect an ordinary feature branch"
assert_equals "1" "$(branch_is_protected feature/NA-1 && echo 0 || echo 1)"

it "does not protect a branch that merely starts with a protected word"
assert_equals "1" "$(branch_is_protected releases-old && echo 0 || echo 1)"

it "classifies a merged release branch as protected, not as merged"
assert_equals "PROTECTED" "$(classify_branch "$(id_of release/6.25)")"

it "records the verdict in the scan, so the list and the plan agree"
assert_equals "true" "$(branch_field "$(id_of release/6.25)" 14)"

it "labels it PROTECTED in the list"
assert_contains "$(branch_display_rows | grep 'release/6.25')" "PROTECTED"

it "leaves it out of the pre-selected candidates"
assert_equals "" "$(
    branch_display_rows |
        awk -F ' \| ' '$2 ~ /^ *(MERGED|ABANDONED) *$/' |
        grep 'release/6.25' || true
)"

#
# The last line of defence: every deletion goes through this function, so a
# future caller cannot route around the plan.
#
it "refuses to delete it even when asked directly"
output="$(force_delete_branch release/6.25 2>&1 || true)"
assert_contains "$output" "Refusing to delete protected branch"

it "leaves the branch in place after that refusal"
assert_equals "release/6.25" "$(git -C "$REPO" branch --list release/6.25 | tr -d ' *')"

it "still deletes an ordinary merged branch"
force_delete_branch merged-by-ancestry >/dev/null 2>&1
assert_equals "" "$(git -C "$REPO" branch --list merged-by-ancestry | tr -d ' *')"

#
# The default is a default, not a policy.
#
it "lets repository configuration replace the pattern"
git -C "$REPO" config cleanup-assistant.protected '^keep/.*$'
resolve_protected_pattern
assert_equals "1" "$(branch_is_protected release/6.25 && echo 0 || echo 1)"

it "protects what that configuration names instead"
assert_equals "0" "$(branch_is_protected keep/forever && echo 0 || echo 1)"

it "lets the environment override the configuration"
GIT_CLEANUP_ASSISTANT_PROTECTED='^never-touch$' resolve_protected_pattern
assert_equals "^never-touch$" "$PROTECTED_PATTERN"

summary
