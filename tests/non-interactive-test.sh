#!/usr/bin/env bash

#
# The non-interactive modes run unattended, from a timer, on a machine nobody is
# looking at. Everything that the interactive plan holds back behind a question
# has to be held back here by the rules alone, because there is nobody to ask.
#
# The suite drives the real script as a process, with a fake gum that records
# every call and a fake gh, so "never a prompt" and "no update check" are
# asserted rather than assumed.
#

set -u

# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gca-noninteractive.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
make_test_repository "$REPO"

#
# A fake gum that fails every call and writes it down: any prompt in a
# non-interactive run shows up in this file.
#
FAKEBIN="$WORK/bin"
GUM_CALLS="$WORK/gum-calls.txt"
GH_CALLS="$WORK/gh-calls.txt"
mkdir -p "$FAKEBIN"

cat > "$FAKEBIN/gum" <<EOF
#!/bin/sh
echo "gum \$*" >> "$GUM_CALLS"
exit 1
EOF

# No GitHub: gh is installed but not authenticated, the path that used to offer
# 'gh auth login' through a prompt.
cat > "$FAKEBIN/gh" <<EOF
#!/bin/sh
echo "gh \$*" >> "$GH_CALLS"
exit 1
EOF

chmod +x "$FAKEBIN/gum" "$FAKEBIN/gh"

#
# The submodule whose pointer integration tests move. It is what the ignored
# dirty path exists for, so it is a real submodule rather than a file standing
# in for one.
#
CONTRACTS="$WORK/contracts"
mkdir -p "$CONTRACTS"
git -C "$CONTRACTS" init -q -b main
git -C "$CONTRACTS" config user.email "test@example.com"
git -C "$CONTRACTS" config user.name "Test"
git -C "$CONTRACTS" config commit.gpgsign false
echo contract > "$CONTRACTS/contract.json"
git -C "$CONTRACTS" add contract.json
git -C "$CONTRACTS" commit -qm "contract"

git -C "$REPO" -c protocol.file.allow=always \
    submodule add -q "$CONTRACTS" api-contracts >/dev/null 2>&1
git -C "$REPO" commit -qm "add api-contracts"

wt() {
    git -C "$REPO" worktree add -q "$@" >/dev/null 2>&1
}

wt "$WORK/wt-merged" merged-by-ancestry
wt "$WORK/wt-squashed" squashed
wt "$WORK/wt-unmerged" unmerged
wt -b dirty-merged "$WORK/wt-dirty" main
wt -b locked-merged "$WORK/wt-locked" main
wt -b release/1 "$WORK/wt-protected" main
wt --detach "$WORK/wt-detached-merged" main~1
wt --detach "$WORK/wt-detached-squashed" squashed
wt --detach "$WORK/wt-detached-unmerged" unmerged
wt -b ignored-merged "$WORK/wt-ignored" main
wt -b ignored-plus "$WORK/wt-ignored-plus" main

echo "uncommitted" >> "$WORK/wt-dirty/file.txt"
git -C "$REPO" worktree lock "$WORK/wt-locked"

#
# Moves the submodule pointer in a worktree the way an integration test run
# does: a new commit inside the checked-out submodule.
#
move_contracts_pointer() {
    local worktree="$1"

    git -C "$worktree" -c protocol.file.allow=always \
        submodule update -q --init api-contracts >/dev/null 2>&1

    git -C "$worktree/api-contracts" -c user.email=t@e.com -c user.name=T \
        -c commit.gpgsign=false commit -q --allow-empty -m "pattern"
}

move_contracts_pointer "$WORK/wt-ignored"
move_contracts_pointer "$WORK/wt-ignored-plus"
echo "real work" >> "$WORK/wt-ignored-plus/file.txt"

UNMERGED_SHA="$(git -C "$REPO" rev-parse unmerged)"

OUTPUT=""
STATUS=0

run_assistant() {
    local bin="$1"
    shift

    OUTPUT="$(
        cd "$REPO" &&
            PATH="$bin:$PATH" "$BASH" "$ASSISTANT" "$@" < /dev/null 2>&1
    )"
    STATUS=$?
}

worktree_listed() {
    git -C "$REPO" worktree list --porcelain | grep -qx "worktree $1"
}

assert_kept() {
    if worktree_listed "$1" && [[ -d "$1" ]]; then
        pass
    else
        fail "expected $1 to be kept"
    fi
}

assert_removed() {
    if ! worktree_listed "$1" && [[ ! -d "$1" ]]; then
        pass
    else
        fail "expected $1 to be removed"
    fi
}

assert_status() {
    assert_equals "$1" "$STATUS"
}

echo "Arguments"

run_assistant "$FAKEBIN" --no-such-flag

it "rejects an unknown flag with a usage error"
assert_status 2

it "names the flag it did not understand"
assert_contains "$OUTPUT" "--no-such-flag"

run_assistant "$FAKEBIN" --delete-branches

it "refuses --delete-branches on its own"
assert_status 2

run_assistant "$FAKEBIN" --help

it "prints usage and exits 0"
assert_status 0

it "documents the new flags"
assert_contains "$OUTPUT" "--apply-merged"

echo
echo "Quiet period"

#
# Every worktree above was created a moment ago, which is the case the quiet
# period exists for: a fresh worktree on the base ref is "merged" by ancestry and
# clean, and removing it would pull it out from under whoever just created it.
#
BEFORE="$(git -C "$REPO" worktree list --porcelain)"

run_assistant "$FAKEBIN" --apply-merged

it "keeps merged worktrees whose HEAD moved in the last 7 days by default"
assert_equals "$BEFORE" "$(git -C "$REPO" worktree list --porcelain)"

it "names them as waiting rather than dropping them silently"
assert_contains "$OUTPUT" "merged, but used recently"

run_assistant "$FAKEBIN" --apply-merged --min-idle-days x

it "rejects a quiet period that is not a number"
assert_status 2

echo
echo "--plan"

BEFORE="$(git -C "$REPO" worktree list --porcelain)"
BRANCHES_BEFORE="$(git -C "$REPO" for-each-ref --format='%(refname)' refs/heads)"

run_assistant "$FAKEBIN" --plan --min-idle-days 0

it "exits 0"
assert_status 0

it "changes no worktree"
assert_equals "$BEFORE" "$(git -C "$REPO" worktree list --porcelain)"

it "changes no branch"
assert_equals "$BRANCHES_BEFORE" "$(git -C "$REPO" for-each-ref --format='%(refname)' refs/heads)"

it "prints the worktree plan"
assert_contains "$OUTPUT" "Worktree Removal Plan"

it "prints the branch plan"
assert_contains "$OUTPUT" "Deletion Plan"

it "holds dirty and locked worktrees back as a state"
assert_contains "$OUTPUT" "dirty or locked"

it "names a detached worktree by its commit"
assert_contains "$OUTPUT" "(detached $(git -C "$REPO" rev-parse --short main~1))"

it "says what --apply-merged would remove, out of how many"
assert_contains "$OUTPUT" "4 of 11 worktrees"

it "never calls gum"
assert_equals "no" "$([[ -s "$GUM_CALLS" ]] && echo yes || echo no)"

it "does not check for an update"
assert_equals "" "$(grep releases "$GH_CALLS" 2>/dev/null || true)"

echo
echo "--apply-merged"

run_assistant "$FAKEBIN" --apply-merged --min-idle-days 0

it "exits 0"
assert_status 0

it "removes a clean worktree whose branch is on the base ref by ancestry"
assert_removed "$WORK/wt-merged"

it "removes a clean worktree whose branch was squash-merged"
assert_removed "$WORK/wt-squashed"

it "removes a clean detached worktree whose HEAD is on the base ref"
assert_removed "$WORK/wt-detached-merged"

it "removes a clean detached worktree whose HEAD was squash-merged"
assert_removed "$WORK/wt-detached-squashed"

it "keeps a dirty worktree even though its branch is merged"
assert_kept "$WORK/wt-dirty"

it "keeps a locked worktree even though its branch is merged"
assert_kept "$WORK/wt-locked"

it "keeps the worktree of a protected branch"
assert_kept "$WORK/wt-protected"

it "keeps a worktree with no evidence either way"
assert_kept "$WORK/wt-unmerged"

it "keeps a detached worktree with no evidence either way"
assert_kept "$WORK/wt-detached-unmerged"

it "keeps the primary worktree"
assert_kept "$REPO"

it "counts a moved submodule pointer as dirty when nothing is configured"
assert_kept "$WORK/wt-ignored"

it "prints one line per removal with the path"
assert_contains "$OUTPUT" "$WORK/wt-merged"

it "says why it removed it"
assert_contains "$OUTPUT" "merged-by-ancestry is on main"

it "prints the command that restores it"
assert_contains "$OUTPUT" "restore: git worktree add $WORK/wt-merged merged-by-ancestry"

it "prints the restore command for a detached worktree with its commit"
assert_contains "$OUTPUT" "git worktree add --detach $WORK/wt-detached-merged $(git -C "$REPO" rev-parse main~1)"

it "reports what it kept and why"
assert_contains "$OUTPUT" "dirty or locked"

it "deletes no branch without --delete-branches"
assert_equals "$BRANCHES_BEFORE" "$(git -C "$REPO" for-each-ref --format='%(refname)' refs/heads)"

it "never calls gum"
assert_equals "no" "$([[ -s "$GUM_CALLS" ]] && echo yes || echo no)"

echo
echo "Ignored dirty path"

git -C "$REPO" config cleanup-assistant.ignore-dirty api-contracts

run_assistant "$FAKEBIN" --apply-merged --min-idle-days 0

it "treats a worktree whose only change is the ignored path as clean"
assert_removed "$WORK/wt-ignored"

it "still keeps a worktree with other changes beside the ignored path"
assert_kept "$WORK/wt-ignored-plus"

it "still keeps a genuinely dirty worktree"
assert_kept "$WORK/wt-dirty"

git -C "$REPO" config --unset cleanup-assistant.ignore-dirty

echo
echo "Detached HEAD with a merged pull request"

GH_FAKEBIN="$WORK/bin-gh"
mkdir -p "$GH_FAKEBIN"
cp "$FAKEBIN/gum" "$GH_FAKEBIN/gum"

cat > "$GH_FAKEBIN/gh" <<EOF
#!/bin/sh
echo "gh \$*" >> "$GH_CALLS"
case "\$*" in
    "auth status"*) exit 0 ;;
    "repo view"*) echo "owner/repo"; exit 0 ;;
    *"repos/owner/repo/commits/$UNMERGED_SHA/pulls"*)
        printf 'merged\t42\thttps://example.test/pull/42\n'
        exit 0
        ;;
esac
exit 0
EOF

chmod +x "$GH_FAKEBIN/gh"
: > "$GH_CALLS"

run_assistant "$GH_FAKEBIN" --apply-merged --min-idle-days 0

it "removes a detached worktree whose commit is in a merged pull request"
assert_removed "$WORK/wt-detached-unmerged"

it "names the pull request as the reason"
assert_contains "$OUTPUT" "pull request #42"

it "still keeps the branch worktree nothing vouches for"
assert_kept "$WORK/wt-unmerged"

it "does not check for an update even with GitHub available"
assert_equals "" "$(grep releases "$GH_CALLS" 2>/dev/null || true)"

echo
echo "--delete-branches"

run_assistant "$FAKEBIN" --apply-merged --delete-branches --min-idle-days 0

branch_exists() {
    git -C "$REPO" rev-parse --verify --quiet "refs/heads/$1" >/dev/null
}

it "deletes a merged branch that no worktree holds any more"
assert_equals "no" "$(branch_exists merged-by-ancestry && echo yes || echo no)"

it "prints the command that restores it"
assert_contains "$OUTPUT" "restore: git branch merged-by-ancestry"

it "keeps an unmerged branch"
assert_equals "yes" "$(branch_exists unmerged && echo yes || echo no)"

it "keeps a protected branch"
assert_equals "yes" "$(branch_exists release/1 && echo yes || echo no)"

it "keeps a merged branch that a kept worktree still holds"
assert_equals "yes" "$(branch_exists dirty-merged && echo yes || echo no)"

it "keeps the primary branch"
assert_equals "yes" "$(branch_exists main && echo yes || echo no)"

summary
