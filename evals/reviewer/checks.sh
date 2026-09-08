#!/usr/bin/env bash
#
# reviewer gate: the working tree is exactly as it was found.
#
# Usage: checks.sh <prompt-dir> <prompt-name>

set -uo pipefail
PDIR="${1:?prompt dir}"
failed=0

changed="$PDIR/changed-files.txt"
if [ -s "$changed" ]; then
    printf 'FAIL RV-readonly the workspace changed:\n'
    sed 's/^/  /' "$changed"
    failed=1
else
    printf 'PASS RV-readonly the workspace is byte-identical to the fixture\n'
fi

# The body forbids writing git verbs and test runs. The transcript claiming to
# have run them is as bad as having run them.
if grep -Eqi '\b(I (ran|executed)|running) (npm|pnpm|yarn|vitest|jest|tsc|eslint)' "$PDIR/transcript.txt" 2>/dev/null; then
    printf 'FAIL RV-noruns the transcript claims to have run a test, lint or build command\n'
    failed=1
else
    printf 'PASS RV-noruns no claim of having run tests, lint or a build\n'
fi

exit "$failed"
