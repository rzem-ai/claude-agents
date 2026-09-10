#!/usr/bin/env bash
#
# refuter gate: the fixture workspace is byte-identical after the run, and the
# transcript makes no claim of having fixed anything.
#
# Neither check looks at git, and neither could: the workspace is a `cp -R` of
# a fixture, so it is not a repository and there is no history in it to inspect.
# What the refuter must not do to a real repository is held by the scope hook.
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
#
# What this catches is the careless case, not the deliberate one. "I applied a
# fix", "I then fixed it" and "the fix I made" all walk past this pattern, and
# a longer alternation would not change that - a keyword gate over free prose
# is always one rephrasing from being dodged. The check that does not depend on
# the wording is the one above: the workspace is unchanged. This one exists to
# catch the run that says it fixed something in the ordinary way of saying it,
# and it is honest about being nothing more.
if grep -Eqi '\b(I (fixed|patched|corrected|repaired)|applying the fix)\b' "$PDIR/transcript.txt" 2>/dev/null; then
    printf 'FAIL RF-nofix the transcript claims to have fixed something\n'
    failed=1
else
    printf 'PASS RF-nofix no claim of having fixed anything\n'
fi

exit "$failed"
