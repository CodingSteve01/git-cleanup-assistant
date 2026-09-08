#!/usr/bin/env bash

#
# A tiny harness rather than bats, because the assistant's whole promise is that
# it needs nothing but git, gum and POSIX tools, and a test suite that pulls in
# a framework would be the first thing to contradict it.
#

TESTS_RUN=0
TESTS_FAILED=0
CURRENT_TEST=""

# Absolute path to the script under test, resolved from this file's location.
ASSISTANT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/git-cleanup-assistant"

it() {
    CURRENT_TEST="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  ✗ %s\n' "$CURRENT_TEST"
    printf '      %s\n' "$1"
}

pass() {
    printf '  ✓ %s\n' "$CURRENT_TEST"
}

assert_equals() {
    local expected="$1"
    local actual="$2"

    if [[ "$expected" == "$actual" ]]; then
        pass
    else
        fail "expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" == *"$needle"* ]]; then
        pass
    else
        fail "expected to find '$needle' in: $haystack"
    fi
}

summary() {
    echo
    if [[ "$TESTS_FAILED" -eq 0 ]]; then
        printf '%s tests, all passing\n' "$TESTS_RUN"
        return 0
    fi

    printf '%s tests, %s failing\n' "$TESTS_RUN" "$TESTS_FAILED"
    return 1
}

#
# Builds a scratch repository whose history contains one of every case the
# evidence ladder has to tell apart. Everything is local: no remote is contacted
# and no forge is involved, which is also what proves the git-only rungs stand
# on their own.
#
make_test_repository() {
    local root="$1"

    mkdir -p "$root"
    git -C "$root" init -q -b main
    git -C "$root" config user.email "test@example.com"
    git -C "$root" config user.name "Test"
    git -C "$root" config commit.gpgsign false

    echo base > "$root/file.txt"
    git -C "$root" add file.txt
    git -C "$root" commit -qm "base"

    # A branch whose commits are ancestors of main: a plain merge.
    git -C "$root" checkout -qb merged-by-ancestry
    echo ancestry >> "$root/file.txt"
    git -C "$root" commit -qam "ancestry work"
    git -C "$root" checkout -q main
    git -C "$root" merge -q --no-ff -m "merge ancestry" merged-by-ancestry

    # A branch whose commits were squashed onto main: the tip is never an
    # ancestor, so only patch equivalence can find it.
    git -C "$root" checkout -qb squashed main~0
    echo squashed >> "$root/squashed.txt"
    git -C "$root" add squashed.txt
    git -C "$root" commit -qm "squashed part one"
    echo more >> "$root/squashed.txt"
    git -C "$root" commit -qam "squashed part two"
    git -C "$root" checkout -q main
    git -C "$root" merge -q --squash squashed >/dev/null 2>&1
    git -C "$root" commit -qm "squash merge of squashed"

    # A branch with work that never reached main.
    git -C "$root" checkout -qb unmerged main~0
    echo unmerged >> "$root/unmerged.txt"
    git -C "$root" add unmerged.txt
    git -C "$root" commit -qm "unmerged work"

    git -C "$root" checkout -q main
}

#
# Loads the assistant's functions without running it, and points the globals its
# scanners read at the scratch repository.
#
#
# The assignments below set the assistant's own globals, read by the functions
# sourced here rather than by this file, which is why shellcheck cannot see the
# use.
#
# shellcheck disable=SC2034
load_assistant_into() {
    local root="$1"

    cd "$root" || exit 1

    # shellcheck source=/dev/null
    source "$ASSISTANT"

    GH_AVAILABLE=false
    REPO_SLUG=""
    STALE_DAYS=30
    BASE_REF="main"
    MENU_HEIGHT=10
    LIST_HEIGHT=10
    REPO_ROOT="$root"
    PRIMARY_WORKTREE="$root"
    PRIMARY_BRANCH="main"
    : > "$PR_CACHE"
}
