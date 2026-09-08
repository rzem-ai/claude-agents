#!/usr/bin/env bash
#
# spec-writer gate: writes land under docs/specs/ and nowhere else.
#
# Usage: checks.sh <prompt-dir> <prompt-name>

set -uo pipefail
PDIR="${1:?prompt dir}"
failed=0

changed="$PDIR/changed-files.txt"

if [ ! -s "$changed" ]; then
    printf 'PASS SW-paths nothing was written\n'
else
    stray=$(grep -v '^\./docs/specs/' "$changed" || true)
    if [ -n "$stray" ]; then
        printf 'FAIL SW-paths wrote outside docs/specs/:\n'
        printf '%s\n' "$stray" | sed 's/^/  /'
        failed=1
    else
        printf 'PASS SW-paths every write landed under docs/specs/\n'
    fi
fi

# The plan directory is the specific line the body draws.
if grep -q '^\./docs/plans/' "$changed" 2>/dev/null; then
    printf 'FAIL SW-noplans wrote into docs/plans/, which belongs to the lead\n'
    failed=1
else
    printf 'PASS SW-noplans nothing written into docs/plans/\n'
fi

exit "$failed"
