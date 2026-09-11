#!/usr/bin/env bash
#
# handoff-extractor-parity.sh - hold review-round's handoff reader to the hook's.
#
# There are now three readers of the handoff format in the claude-agents repo:
#
#   claude-agents/hooks/board-subagent-stop.sh   extract_section   (the board)
#   evals/lib/handoff-check.sh                   the CI validator
#   claude-agents/workflows/review-round.js      handoffSection    (the fix loop)
#
# The first two are already pinned to each other by handoff-parity.sh. This
# pins the third. It matters because review-round reads coder's "## Done"
# bullets for the worktree and commit hints and its "## Not done" bullets for
# a finding's disposition, so a reader that disagrees with the hook about what
# an item IS would make the fix loop and the card disagree about the same run.
#
# The two implementations are sliced out of their files rather than
# reimplemented here, so this compares the shipping code and not a copy of it.
# The known-hard cases are the ones the hook spells out and a naive reader gets
# wrong: CRLF (the hook strips every \r), right-trimmed headings ("## Done "
# with a trailing space opens the section - trailing whitespace is invisible
# and never changes meaning), and the None filter's preserved leading
# whitespace ("-  None", two spaces after the dash, is a real item).
#
# Usage:  evals/lib/handoff-extractor-parity.sh [-v]

set -uo pipefail

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

LIB_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$LIB_DIR/../.." && pwd)
HOOK="$REPO_ROOT/claude-agents/hooks/board-subagent-stop.sh"
WORKFLOW="$REPO_ROOT/claude-agents/workflows/review-round.js"
CASES="$REPO_ROOT/evals/fixtures/handoff-cases"

command -v jq >/dev/null 2>&1 || { printf 'handoff-extractor-parity: jq is needed\n' >&2; exit 2; }
command -v node >/dev/null 2>&1 || { printf 'handoff-extractor-parity: node is needed\n' >&2; exit 2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/handoff-extractor.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

# Slice each implementation out of the file it ships in. Anchored on the
# function's own opening line and its closing brace at column 0, so a rename
# breaks this loudly rather than silently comparing nothing.
sed -n '/^extract_section() {$/,/^}$/p' "$HOOK" > "$TMP/hook.sh"
sed -n '/^function handoffSection(msg, name) {$/,/^}$/p' "$WORKFLOW" > "$TMP/wf.js"

[ -s "$TMP/hook.sh" ] || { printf 'handoff-extractor-parity: could not slice extract_section out of the hook\n' >&2; exit 2; }
[ -s "$TMP/wf.js" ]   || { printf 'handoff-extractor-parity: could not slice handoffSection out of review-round.js\n' >&2; exit 2; }

# shellcheck source=/dev/null
. "$TMP/hook.sh"

cat >> "$TMP/wf.js" <<'JS'
const [, , file, section] = process.argv
const msg = require('fs').readFileSync(file, 'utf8')
process.stdout.write(handoffSection(msg, section).join('\n'))
JS

PASSED=0
FAILED=0
SECTIONS=("Done" "Not done" "Unverified" "Decisions needed")

# Extra cases beyond the shared fixtures: the three shapes the hook's own rules
# single out, which a reader written from the prose rather than the code gets
# wrong in three different ways.
mk() { printf '%b' "$2" > "$TMP/$1"; printf '%s\n' "$TMP/$1"; }
EXTRA=()
EXTRA+=("$(mk crlf.txt '## Done\r\n- one\r\n\r\n## Not done\r\n- None\r\n\r\n## Unverified\r\n- None\r\n\r\n## Decisions needed\r\n- None\r\n')")
EXTRA+=("$(mk trailing-space-heading.txt '## Done \n- one\n\n## Not done\n- None\n')")
EXTRA+=("$(mk none-two-spaces.txt '## Done\n-  None\n\n## Not done\n- None\n')")
EXTRA+=("$(mk none-trailing-tab.txt '## Done\n- None\t\n\n## Not done\n- x\n')")

for f in "$CASES"/*.txt "${EXTRA[@]}"; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    for section in "${SECTIONS[@]}"; do
        # The hook keeps each line's "- " because it posts them to a card
        # verbatim; handoffSection returns the item text because it parses it.
        # That difference is presentational, so it is normalised away here -
        # what must agree, and what this pins, is WHICH lines each one selects.
        want=$(extract_section "$section" "$(cat "$f")" | sed 's/^- //')
        got=$(node "$TMP/wf.js" "$f" "$section")
        if [ "$want" = "$got" ]; then
            PASSED=$((PASSED + 1))
            [ "$VERBOSE" -eq 1 ] && printf '  ok    %-34s %s\n' "$name" "$section"
        else
            FAILED=$((FAILED + 1))
            printf '  FAIL  %-34s %s\n' "$name" "$section"
            printf '        hook:     %s\n' "$(printf '%s' "$want" | tr '\n' '|')"
            printf '        workflow: %s\n' "$(printf '%s' "$got" | tr '\n' '|')"
        fi
    done
done

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    printf "review-round reads a handoff differently from the hook that validates it, so the fix loop and the card can disagree about the same run.\n"
    exit 1
fi
printf 'The fix loop reads a handoff exactly as the board hook does.\n'
