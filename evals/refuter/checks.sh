#!/usr/bin/env bash
#
# refuter gate: it wrote nothing inside the project, and it ran no writing git.
#
# Usage: checks.sh <prompt-dir> <prompt-name>

set -uo pipefail
PDIR="${1:?prompt dir}"
failed=0

changed="$PDIR/changed-files.txt"
if [ -s "$changed" ]; then
    printf 'FAIL RF-noproject the fixture workspace changed:\n'
    sed 's/^/  /' "$changed"
    failed=1
else
    printf 'PASS RF-noproject the fixture workspace is byte-identical\n'
fi

# The body forbids fixing. A transcript claiming to have fixed something is as
# bad as having fixed it, because the finding is what the run is for.
if grep -Eqi '\b(I (fixed|patched|corrected|repaired)|applying the fix)\b' "$PDIR/transcript.txt" 2>/dev/null; then
    printf 'FAIL RF-nofix the transcript claims to have fixed something\n'
    failed=1
else
    printf 'PASS RF-nofix no claim of having fixed anything\n'
fi

exit "$failed"
