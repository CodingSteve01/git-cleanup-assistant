#!/usr/bin/env bash

#
# An ignored dirty path is a hole in the one check that protects uncommitted
# work, so it has to be exactly as wide as configured: the path itself and what
# lies below it, never a sibling that merely starts with the same letters.
#

set -u

# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gca-ignore.XXXXXX")" && pwd -P)"

REPO="$WORK/repo"
make_test_repository "$REPO"
load_assistant_into "$REPO"

# Sourcing the assistant replaced the trap above with its own.
trap 'cleanup_tmp; rm -rf "$WORK"' EXIT

echo "Ignored dirty paths"

it "ignores nothing unless configured"
unset GIT_CLEANUP_ASSISTANT_IGNORE_DIRTY
resolve_ignore_dirty_paths
assert_equals "" "$IGNORE_DIRTY_PATHS"

it "passes every change through when nothing is ignored"
assert_equals " M api-contracts" "$(printf ' M api-contracts\n' | filter_ignored_changes)"

it "reads git config, including a repeated key and a comma list"
git -C "$REPO" config cleanup-assistant.ignore-dirty "api-contracts, ./generated/"
git -C "$REPO" config --add cleanup-assistant.ignore-dirty "api-contracts"
resolve_ignore_dirty_paths
assert_equals "api-contracts,generated" "$(printf '%s' "$IGNORE_DIRTY_PATHS" | tr '\n' ',')"

it "lets the environment win over git config"
export GIT_CLEANUP_ASSISTANT_IGNORE_DIRTY="other"
resolve_ignore_dirty_paths
assert_equals "other" "$IGNORE_DIRTY_PATHS"
unset GIT_CLEANUP_ASSISTANT_IGNORE_DIRTY
resolve_ignore_dirty_paths

it "drops the ignored path itself"
assert_equals "" "$(printf ' M api-contracts\n' | filter_ignored_changes)"

it "drops what lies below the ignored path"
assert_equals "" "$(printf '?? generated/a/b.json\n' | filter_ignored_changes)"

it "keeps a sibling that only shares the prefix"
assert_equals " M api-contracts-old" "$(printf ' M api-contracts-old\n' | filter_ignored_changes)"

it "keeps every other change"
assert_equals " M file.txt" "$(printf ' M api-contracts\n M file.txt\n' | filter_ignored_changes)"

it "judges a rename by where it went"
assert_equals "R  file.txt -> moved.txt" \
    "$(printf 'R  file.txt -> moved.txt\nR  x -> generated/x\n' | filter_ignored_changes)"

git -C "$REPO" config --unset-all cleanup-assistant.ignore-dirty

summary
