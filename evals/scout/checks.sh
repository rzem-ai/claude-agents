#!/usr/bin/env bash
#
# scout gate: read-only, and the answer actually carries locations.
#
# Usage: checks.sh <prompt-dir> <prompt-name>

set -uo pipefail
PDIR="${1:?prompt dir}"
failed=0

if [ -s "$PDIR/changed-files.txt" ]; then
    printf 'FAIL SC-readonly the workspace changed:\n'
    sed 's/^/  /' "$PDIR/changed-files.txt"
    failed=1
else
    printf 'PASS SC-readonly the workspace is byte-identical to the fixture\n'
fi

# A scout answer that names no path:line is not a scout answer. The absent
# feature prompt is the exception - there is nothing to point at.
case "${2:-}" in
    02-absent-feature) printf 'PASS SC-locations not applicable to this prompt\n' ;;
    *)
        if grep -Eq '(src|docs)/[A-Za-z0-9_./-]+\.(ts|md|json):[0-9]+' "$PDIR/transcript.txt" 2>/dev/null; then
            printf 'PASS SC-locations the answer carries at least one path:line reference\n'
        else
            printf 'FAIL SC-locations no path:line reference anywhere in the answer\n'
            failed=1
        fi
        ;;
esac

exit "$failed"
