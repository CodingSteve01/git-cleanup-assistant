#!/usr/bin/env bash

#
# Every prompt names what it acts on, and every list can be read to the end.
#
# The screen that prompted this suite was the review of a dirty worktree: its
# `git status` went straight to the terminal, so four hundred changed files
# pushed the branch name, the path and the state out of the scrollback, and the
# question underneath them read "What should happen to this worktree?" without
# naming which one. The option that discards the work was two keystrokes below a
# screen that no longer said whose work it was.
#
# The rules the tests below hold in place:
#   - a prompt header names its subject and its position in a run
#   - a list is previewed to a fixed number of lines and the rest is counted
#   - the full list is one menu entry away, in a pager that scrolls
#   - a typed confirmation repeats what is about to be destroyed
#

set -u

# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gca-disclosure.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
make_test_repository "$REPO"
load_assistant_into "$REPO"

echo "Change summaries"

it "says what kind of change it found, not just how many"
summary="$(
    printf ' M a.txt\n M b.txt\n D gone.txt\n?? new.txt\n' | summarize_changes
)"
assert_equals "4 changes: 2 modified, 1 deleted, 1 untracked" "$summary"

it "counts a staged rename as a rename"
assert_equals "1 change: 1 renamed" "$(printf 'R  old.txt -> new.txt\n' | summarize_changes)"

it "counts a staged addition as an addition"
assert_equals "1 change: 1 added" "$(printf 'A  added.txt\n' | summarize_changes)"

it "names a conflict, because it is not an ordinary modification"
assert_equals "1 change: 1 conflicted" "$(printf 'UU both.txt\n' | summarize_changes)"

it "keeps the singular for one change"
assert_equals "1 change: 1 modified" "$(printf ' M a.txt\n' | summarize_changes)"

it "says so plainly when there is nothing uncommitted"
assert_equals "no uncommitted changes" "$(printf '' | summarize_changes)"

it "reads the real worktree and writes the full list to a file"
echo more >> "$REPO/file.txt"
echo fresh > "$REPO/untracked.txt"
changes="$WORK/changes.txt"
assert_equals "2 changes: 1 modified, 1 untracked" "$(describe_changes "$REPO" "$changes")"

it "keeps every change in that file, whatever the summary says"
assert_equals "2" "$(count_rows "$changes")"

echo
echo "Bounded previews"

printf 'line %s\n' 1 2 3 4 5 6 7 8 9 10 11 12 > "$WORK/long.txt"

it "shows only the first lines of a long list"
assert_equals "3" "$(preview_file "$WORK/long.txt" 3 | grep -c '^    line')"

it "counts what it held back instead of dumping it"
assert_contains "$(preview_file "$WORK/long.txt" 3)" "and 9 more"

it "says nothing about a remainder when the list fits"
assert_equals "0" "$(preview_file "$WORK/long.txt" 12 | grep -c 'more')"

it "prints nothing at all for an empty list"
: > "$WORK/empty.txt"
assert_equals "" "$(preview_file "$WORK/empty.txt" 5)"

#
# A preview that does not fit is only a shorter dump: it still pushes the subject
# of the question off the top of the screen.
#
it "leaves room for the header block and the menu on a small terminal"
assert_equals "6" "$(preview_limit_for_terminal 24)"

it "never shrinks below a few lines, however small the terminal claims to be"
assert_equals "3" "$(preview_limit_for_terminal 10)"

it "stops growing on a tall terminal, so the subject stays in view"
assert_equals "12" "$(preview_limit_for_terminal 200)"

it "falls back to a default when the terminal size is not a number"
assert_equals "6" "$(preview_limit_for_terminal "not-a-number")"

echo
echo "Subjects"

it "names the position inside a run of several"
assert_equals "feature/x (2 of 7)" "$(subject_with_position "feature/x" 2 7)"

it "leaves the position out when the subject is alone"
assert_equals "feature/x" "$(subject_with_position "feature/x" 1 1)"

it "leaves the position out when there is none"
assert_equals "feature/x" "$(subject_with_position "feature/x")"

#
# The expected value is built rather than written, because an unexpanded tilde in
# a quoted string is the kind of literal shellcheck is right to flag.
#
it "shortens a path under the home directory, where the end is the useful half"
expected="$(printf '~%s' "/worktrees/voffice/x")"
assert_equals "$expected" "$(short_path "$HOME/worktrees/voffice/x")"

it "shortens the home directory itself"
assert_equals "$(printf '~')" "$(short_path "$HOME")"

it "leaves a path outside the home directory alone"
assert_equals "/opt/repos/x" "$(short_path "/opt/repos/x")"

#
# A prefix match, not a string match: /home/runner-2 is not inside /home/runner.
#
it "does not shorten a path that merely starts with the same letters"
assert_equals "${HOME}-elsewhere/x" "$(short_path "${HOME}-elsewhere/x")"

echo
echo "Evidence read out in words"

it "names the rung of the ladder behind a class"
assert_contains "$(describe_evidence PROVEN)" "already on main"

it "says plainly when there is no signal either way"
assert_contains "$(describe_evidence UNKNOWN)" "no signal"

#
# "unknown" is what a run without gh reports, and on a review screen that reads
# as though GitHub had been asked and shrugged.
#
it "distinguishes an unasked forge from a branch with no pull request"
assert_contains "$(describe_pr_state unknown)" "not checked"

it "says so when the forge was asked and found nothing"
assert_equals "none found" "$(describe_pr_state none)"

it "passes a real state through as it is"
assert_equals "merged" "$(describe_pr_state merged)"

echo
echo "Confirmations that can be checked before they are answered"

#
# gum never runs here: the pager is stubbed out and the menu is scripted, so the
# confirmation is exercised without a terminal.
#
# One definition of each, driven by variables rather than redefined per case:
# redefining a function makes the earlier body look unreachable, which the older
# linter releases report and the newer ones do not.
#
MENU_ANSWER=""
MENU_SECOND_ANSWER=""
MENU_CALLS_FILE="$WORK/menu-calls"
MENU_OFFERED_FILE="$WORK/menu-offered"

: > "$MENU_CALLS_FILE"

# shellcheck disable=SC2317,SC2329
gum() {
    cat >/dev/null 2>&1 || true
}

# shellcheck disable=SC2317,SC2329
menu() {
    shift
    printf '%s\n' "$@" > "$MENU_OFFERED_FILE"
    echo call >> "$MENU_CALLS_FILE"

    if [[ -n "$MENU_SECOND_ANSWER" ]] && [[ "$(count_rows "$MENU_CALLS_FILE")" -gt 1 ]]; then
        echo "$MENU_SECOND_ANSWER"
        return 0
    fi

    echo "$MENU_ANSWER"
}

answers_to() {
    MENU_ANSWER="$1"
    MENU_SECOND_ANSWER="${2:-}"
    : > "$MENU_CALLS_FILE"
}

it "confirms when the affirmative is chosen"
answers_to "Remove these 3 worktrees"
assert_equals "0" "$(
    confirm_with_details "3 worktrees" "Remove these 3 worktrees" "$WORK/long.txt" \
        >/dev/null && echo 0 || echo 1
)"

it "skips when the question is declined"
answers_to "Keep them, decide later"
assert_equals "1" "$(
    confirm_with_details "3 worktrees" "Remove these 3 worktrees" "$WORK/long.txt" \
        >/dev/null && echo 0 || echo 1
)"

#
# gum choose answers with an empty line when it is cancelled, and a cancelled
# question must never read as a yes.
#
it "treats a cancelled menu as a no"
answers_to ""
assert_equals "1" "$(
    confirm_with_details "3 worktrees" "Remove these 3 worktrees" "$WORK/long.txt" \
        >/dev/null && echo 0 || echo 1
)"

it "asks again after the full list was shown, rather than deciding by itself"
answers_to "Show all 12 first" "Keep them, decide later"
confirm_with_details "3 worktrees" "Remove these 3 worktrees" "$WORK/long.txt" \
    >/dev/null 2>&1 || true
assert_equals "2" "$(count_rows "$MENU_CALLS_FILE")"

it "offers the full list with its length, so its size is known before it opens"
answers_to ""
confirm_with_details "3 worktrees" "Remove these 3 worktrees" "$WORK/long.txt" \
    >/dev/null 2>&1 || true
assert_contains "$(cat "$MENU_OFFERED_FILE")" "Show all 12"

unset -f menu
unset -f gum

echo
echo "No anonymous prompt survives in the script"

#
# Structural, in the spirit of the gum-input guard: these exact strings were the
# prompts that named nothing, so a future edit that reintroduces one trips here
# rather than in front of a user with four hundred changed files on screen.
#
# Code lines only, in the shape of the gum-input guard: the prose above each
# call site is allowed to quote the prompt it replaced.
it "never asks what should happen without naming the subject"
assert_equals "0" "$(grep -cE '^[^#]*"What should happen to this worktree\?"' "$ASSISTANT" | tr -d ' ')"

it "never asks a bare 'What should happen?'"
assert_equals "0" "$(grep -cE '^[^#]*"What should happen\?"' "$ASSISTANT" | tr -d ' ')"

it "never asks for a typed DELETE without saying what is deleted"
assert_equals "0" "$(grep -cE '^[^#]*Type DELETE to confirm' "$ASSISTANT" | tr -d ' ')"

#
# --short is the human-readable format and every use of it went to the terminal
# unbounded. The porcelain format goes to a file, which is what the preview and
# the pager read.
#
it "never prints a status listing straight to the terminal"
assert_equals "0" "$(grep -cE '^[^#]*status --short' "$ASSISTANT" | tr -d ' ')"

summary
