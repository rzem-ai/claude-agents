#!/usr/bin/env bash
#
# check-all.sh - every deterministic check in the repository, in one command.
#
# None of these calls a model, opens a network connection, or touches Notion,
# so this is the thing to run before a commit and the thing CI should run. The
# model evals under evals/run.sh are separate and cost money.
#
#   handoff-parity        the two handoff validators agree, 28 fixtures
#   handoff-extractor     review-round reads a handoff exactly as the hook does
#   board-hook-contract   the board hooks read fields the runtime sends
#   scope-hook-contract   each role is held to its invariants, and can still work
#   roster-contract       every agent is known to the matcher, runner and evals
#   workflow-logic        the workflow branches decide on evidence
#   runner-gate           the eval runner fails when the run failed
#   glossary              the generated rule still matches the canonical skill
#
# Usage:  evals/lib/check-all.sh [-v]

set -uo pipefail

VERBOSE="${1:-}"
LIB_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$LIB_DIR/../.." && pwd)

FAILED=()

run() {
    # $1 label, rest: command
    local label="$1"; shift
    printf '\n=== %s ===\n' "$label"
    if "$@" ${VERBOSE:+"$VERBOSE"}; then
        printf '%s: ok\n' "$label"
    else
        printf '%s: FAILED\n' "$label"
        FAILED+=("$label")
    fi
}

printf '\n=== shell and node syntax ===\n'
syntax_failed=0
while IFS= read -r f; do
    bash -n "$f" 2>&1 || { printf '  syntax FAIL %s\n' "$f"; syntax_failed=1; }
done < <(find "$REPO_ROOT/claude-agents/hooks" "$REPO_ROOT/scripts" "$REPO_ROOT/evals" \
            -name '*.sh' -type f 2>/dev/null)
for f in "$REPO_ROOT"/claude-agents/workflows/*.js; do
    node -e "
      const fs=require('fs');
      const src=fs.readFileSync('$f','utf8').replace(/^export const meta/m,'const meta');
      new Function('agent','parallel','pipeline','phase','log','args','return (async()=>{'+src+'})()');
    " 2>&1 || { printf '  parse FAIL %s\n' "$f"; syntax_failed=1; }
done
if [ "$syntax_failed" -eq 0 ]; then printf 'syntax: ok\n'; else FAILED+=("syntax"); fi

run handoff-parity      "$LIB_DIR/handoff-parity.sh"
run handoff-extractor   "$LIB_DIR/handoff-extractor-parity.sh"
run board-hook-contract "$LIB_DIR/board-hook-contract.sh"
run scope-hook-contract "$LIB_DIR/scope-hook-contract.sh"
run roster-contract     "$LIB_DIR/roster-contract.sh"
run workflow-logic      node "$LIB_DIR/workflow-logic.mjs"
run runner-gate         "$LIB_DIR/runner-gate.sh"

printf '\n=== glossary ===\n'
if "$REPO_ROOT/scripts/gen-glossary-rule.sh" --check; then
    printf 'glossary: ok\n'
else
    printf 'glossary: FAILED\n'
    FAILED+=("glossary")
fi

printf '\n---\n'
if [ "${#FAILED[@]}" -ne 0 ]; then
    printf 'FAILED: %s\n' "${FAILED[*]}"
    exit 1
fi
printf 'Every deterministic check passes.\n'
