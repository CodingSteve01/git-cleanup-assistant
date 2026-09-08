#!/usr/bin/env bash

#
# The base ref is what every merge check is measured against, so an unusable one
# does not fail loudly — it makes the whole ladder answer "no evidence" for every
# branch in the repository and the assistant reports that nothing can be cleaned
# up.
#
# That was reachable: an unverifiable answer fell back to a constant origin/main,
# which is exactly the ref that had just failed to resolve.
#

set -u

# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gca-baseref.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
make_test_repository "$REPO"
load_assistant_into "$REPO"

# shellcheck disable=SC2034
PRIMARY_BRANCH=main

echo "Base ref selection"

it "offers only refs that exist"
assert_equals "main" "$(base_ref_candidates)"

it "never offers a remote ref this repository does not have"
assert_equals "" "$(base_ref_candidates | grep '^origin/' || true)"

it "takes the single candidate without asking"
BASE_REF=""
choose_base_ref >/dev/null
assert_equals "main" "$BASE_REF"

#
# A repository whose default branch is not called main is the case the old
# constant got wrong, and it is not exotic.
#
OTHER="$WORK/other"
mkdir -p "$OTHER"
git -C "$OTHER" init -q -b trunk
git -C "$OTHER" config user.email t@e.com
git -C "$OTHER" config user.name T
git -C "$OTHER" config commit.gpgsign false
echo x > "$OTHER/f.txt"
git -C "$OTHER" add f.txt
git -C "$OTHER" commit -qm x

cd "$OTHER" || exit 1

# Read by base_ref_candidates, which is sourced rather than defined here.
# shellcheck disable=SC2034
PRIMARY_BRANCH=trunk

it "finds the primary branch when it is not called main"
assert_equals "trunk" "$(base_ref_candidates)"

it "picks it rather than a constant origin/main"
BASE_REF=""
choose_base_ref >/dev/null
assert_equals "trunk" "$BASE_REF"

#
# origin/HEAD names the remote's default branch, which outranks a guess.
#
git -C "$OTHER" update-ref refs/remotes/origin/release refs/heads/trunk
git -C "$OTHER" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/release

it "asks the remote which branch is its default, first"
assert_equals "origin/release" "$(base_ref_candidates | head -1)"

it "still lists the local branches after it"
assert_contains "$(base_ref_candidates)" "trunk"

summary
