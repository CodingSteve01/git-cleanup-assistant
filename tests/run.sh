#!/usr/bin/env bash

#
# Runs every *-test.sh next to this file and fails if any of them does.
#

set -u

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

status=0

for suite in ./*-test.sh; do
    [[ -e "$suite" ]] || continue

    echo
    echo "── $(basename "$suite")"

    if ! bash "$suite"; then
        status=1
    fi
done

echo

if [[ "$status" -eq 0 ]]; then
    echo "All suites passed."
else
    echo "Some suites failed."
fi

exit "$status"
