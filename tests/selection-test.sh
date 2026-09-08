#!/usr/bin/env bash

#
# A selection of twenty branches has to survive twenty prompts.
#
# The failure this pins down looked like a refused deletion but was a stdin
# problem: `while read ... done < list` owns stdin for the whole loop, so the
# first prompt inside the body read the remaining ids as keystrokes, answered
# itself with them, and every entry after the first was skipped without a word.
# The stand-in below reproduces exactly that: it drains stdin the way a terminal
# UI does, so a loop that reads the selection from stdin can only ever complete
# one pass.
#

set -u

# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gca-selection.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
make_test_repository "$REPO"
load_assistant_into "$REPO"

echo "Selection handling"

it "reads every line of a selection into the array"
load_ids "$(printf 'B00001\nB00002\nB00003\n')"
assert_equals "3" "$(selected_count)"

it "drops blank lines instead of acting on an empty id"
load_ids "$(printf 'B00001\n\nB00002\n')"
assert_equals "2" "$(selected_count)"

it "survives an empty selection under set -u"
load_ids ""
assert_equals "0" "$(selected_count)"

it "keeps ids that contain no whitespace intact"
load_ids "$(printf 'W00001\nB00042\n')"
assert_equals "W00001 B00042" "${SELECTED_IDS[*]}"

#
# The regression itself. A prompt that consumes stdin must not cost the loop the
# rest of its selection.
#
# stdin is pointed at a file of stand-in keystrokes rather than left inherited,
# so the drain terminates and the test can never block waiting for a terminal.
#
KEYSTROKES="$WORK/keystrokes"
printf 'y\ny\ny\n' > "$KEYSTROKES"

prompt_that_drains_stdin() {
    cat >/dev/null
    return 0
}

visit_with_array() {
    local visited=""
    local id

    load_ids "$(printf 'one\ntwo\nthree\n')"

    for id in ${SELECTED_IDS[@]+"${SELECTED_IDS[@]}"}; do
        visited="$visited$id "
        prompt_that_drains_stdin
    done

    printf '%s' "$visited"
}

visit_with_stdin_loop() {
    local visited=""
    local id

    while IFS= read -r id; do
        visited="$visited$id "
        prompt_that_drains_stdin
    done <<< "$(printf 'one\ntwo\nthree\n')"

    printf '%s' "$visited"
}

it "visits every selected id even when each one prompts"
assert_equals "one two three " "$(visit_with_array < "$KEYSTROKES")"

it "shows that the old shape stopped after the first id"
assert_equals "one " "$(visit_with_stdin_loop < "$KEYSTROKES")"

summary
