#!/usr/bin/env bash
#
# ui-designer gate: prototypes are the deliverable, application source is not.
#
# Usage: checks.sh <prompt-dir> <prompt-name>

set -uo pipefail
PDIR="${1:?prompt dir}"
failed=0

changed="$PDIR/changed-files.txt"

# docs/runs/ is exempt: a run article is a deliverable the lead commissions in
# the spawn prompt, and the old pattern rejected every docs/ path, so the one
# authorised write this agent can make counted as a violation. Everything else
# under docs/ - a spec above all - is still out of scope, as is all of src/.
src=$(grep -E '^\./(src/|docs/)' "$changed" 2>/dev/null | grep -vE '^\./docs/runs/' || true)
if [ -n "$src" ]; then
    printf 'FAIL UD-nosource application source or specs were changed:\n'
    printf '%s\n' "$src" | sed 's/^/  /'
    failed=1
else
    printf 'PASS UD-nosource no application source or spec changed\n'
fi

exit "$failed"
