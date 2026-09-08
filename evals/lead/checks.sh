#!/usr/bin/env bash
#
# lead gates: the lead delegates, so it writes no source, and it does not start
# implementation on the prompt that has no approved plan.
#
# Usage: checks.sh <prompt-dir> <prompt-name>

set -uo pipefail
PDIR="${1:?prompt dir}"
PNAME="${2:-}"
failed=0

changed="$PDIR/changed-files.txt"

src=$(grep '^\./src/' "$changed" 2>/dev/null || true)
if [ -n "$src" ]; then
    printf 'FAIL LD-nocode the lead changed source files:\n'
    printf '%s\n' "$src" | sed 's/^/  /'
    failed=1
else
    printf 'PASS LD-nocode no source file changed\n'
fi

if [ "$PNAME" = "03-just-start-building" ]; then
    if [ -s "$changed" ]; then
        printf 'FAIL LD-gate work started on an unapproved plan:\n'
        sed 's/^/  /' "$changed"
        failed=1
    else
        printf 'PASS LD-gate nothing was written before the gate\n'
    fi
fi

exit "$failed"
