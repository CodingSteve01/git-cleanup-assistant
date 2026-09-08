#!/usr/bin/env bash

#
# The two prompts that do not go through gum, and why.
#
# gum 2.0.0 panics whenever its input field is empty. That is the starting state
# of every "Press Enter to continue" and of every "Type DELETE" confirmation, so
# the assistant printed a Go stack trace where it meant to pause, and the typed
# confirmation guarding every destructive path could not be answered at all.
#
# Both are shell builtins now, which is also why a future gum release cannot
# break them again.
#

set -u

# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gca-prompt.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
make_test_repository "$REPO"
load_assistant_into "$REPO"

echo "Prompts"

it "does not call gum input anywhere"
assert_equals "0" "$(grep -c '^[^#]*gum input' "$ASSISTANT" | tr -d ' ')"

it "returns what was typed"
assert_equals "DELETE" "$(printf 'DELETE\n' | prompt_for_line 'Type DELETE: ' 2>/dev/null)"

it "returns nothing when the line is empty, rather than the prompt"
assert_equals "" "$(printf '\n' | prompt_for_line 'Type DELETE: ' 2>/dev/null)"

it "keeps the prompt off stdout, so a substitution gets the answer alone"
assert_equals "yes" "$(printf 'yes\n' | prompt_for_line 'Question: ' 2>/dev/null)"

it "does not treat a typo as confirmation"
typed="$(printf 'delete\n' | prompt_for_line 'Type DELETE: ' 2>/dev/null)"
assert_equals "1" "$([[ "$typed" == "DELETE" ]] && echo 0 || echo 1)"

#
# A run whose stdin is closed must end rather than block: this is what a piped
# or non-interactive invocation looks like.
#
it "returns instead of blocking when stdin is closed"
assert_equals "0" "$(pause < /dev/null >/dev/null 2>&1 && echo 0 || echo 1)"

it "reads only one line, leaving the rest for the next prompt"
result="$(
    printf 'first\nsecond\n' | {
        a="$(prompt_for_line 'one: ' 2>/dev/null)"
        b="$(prompt_for_line 'two: ' 2>/dev/null)"
        printf '%s,%s' "$a" "$b"
    }
)"
assert_equals "first,second" "$result"

summary
