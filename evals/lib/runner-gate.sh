#!/usr/bin/env bash
#
# runner-gate.sh - the eval runner must fail when the thing it evaluated failed.
#
# It used to store the exit code, print a warning, and carry on. If the capture
# happened to contain a valid handoff and the fixture was unchanged, every gate
# passed and the runner exited 0 - so a baseline could be recorded from a run
# that never happened. `final-message.sh` also lifts the `result` string out of
# the envelope without looking at `is_error`, so an error envelope reads as
# ordinary evidence.
#
# The stub below is the review's: one valid handoff, three endings.
#
# Usage:  evals/lib/runner-gate.sh [-v]
#
# No model is called and nothing is graded - CLAUDE_BIN is a shell script.

set -uo pipefail

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

LIB_DIR=$(cd "$(dirname "$0")" && pwd)
EVAL_ROOT=$(cd "$LIB_DIR/.." && pwd)

TMP=$(mktemp -d "${TMPDIR:-/tmp}/runner-gate.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

PASSED=0
FAILED=0

HANDOFF='## Done\n- Looked for the feature; it is not in this fixture.\n\n## Not done\n- Nothing further.\n\n## Unverified\n- None\n\n## Decisions needed\n- None\n'

# $1 is_error, $2 exit code -> path to a stub claude.
# The envelope is built with jq so the handoff's newlines survive into the JSON
# string exactly as the real CLI would emit them.
make_stub() {
    local stub="$TMP/claude-$1-$2" envelope
    envelope=$(jq -nc --arg r "$(printf '%b' "$HANDOFF")" --argjson e "$1" \
        '{type:"result",is_error:$e,result:$r}')
    cat > "$stub" <<EOF
#!/usr/bin/env bash
cat <<'ENVELOPE'
$envelope
ENVELOPE
exit $2
EOF
    chmod +x "$stub"
    printf '%s\n' "$stub"
}

expect_exit() {
    # $1 want (0 or nonzero), $2 label, $3 is_error, $4 stub exit code
    local stub out rc
    stub=$(make_stub "$3" "$4")
    out="$TMP/out-$3-$4"
    EVAL_CLAUDE_BIN="$stub" "$EVAL_ROOT/run.sh" scout --prompt 02 --no-judge \
        --out "$out" > "$TMP/log" 2>&1
    rc=$?
    local ok=1
    if [ "$1" = "0" ]; then [ "$rc" -eq 0 ] && ok=0; else [ "$rc" -ne 0 ] && ok=0; fi
    if [ "$ok" -eq 0 ]; then
        PASSED=$((PASSED + 1))
        [ "$VERBOSE" -eq 1 ] && printf '  ok    %-46s runner exit %s\n' "$2" "$rc"
    else
        FAILED=$((FAILED + 1))
        printf '  FAIL  %-46s runner exit %s, wanted %s\n' "$2" "$rc" "$1"
        [ "$VERBOSE" -eq 1 ] && sed 's/^/        /' "$TMP/log" | tail -12
    fi
    LAST_OUT="$out"
    return 0
}

printf '\nThe runner agrees with the process it ran\n'
expect_exit 0       'a valid handoff and a clean exit passes'            false 0
expect_exit nonzero 'the same handoff with a non-zero exit fails'        false 7
expect_exit nonzero 'the same handoff inside an is_error envelope fails' true  0

printf '\nA run says which definitions it exercised\n'
if [ -f "$LAST_OUT/definition-provenance.json" ] && \
   command -v jq >/dev/null 2>&1 && \
   [ "$(jq -r '.files | length' "$LAST_OUT/definition-provenance.json")" -ge 9 ]; then
    PASSED=$((PASSED + 1))
    [ "$VERBOSE" -eq 1 ] && printf '  ok    %s\n' 'provenance records a hash per definition'
else
    FAILED=$((FAILED + 1))
    printf '  FAIL  %s\n' 'provenance records a hash per definition'
fi

if grep -q -- '--plugin-dir' "$EVAL_ROOT/run.sh" && grep -q 'claude-agents:\$agent' "$EVAL_ROOT/run.sh"; then
    PASSED=$((PASSED + 1))
    [ "$VERBOSE" -eq 1 ] && printf '  ok    %s\n' 'the checkout is loaded and the agent is plugin-scoped'
else
    FAILED=$((FAILED + 1))
    printf '  FAIL  %s\n' 'the checkout is loaded and the agent is plugin-scoped'
fi

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    printf 'The runner can still report a pass for a run that failed.\n'
    exit 1
fi
printf 'The summary verdict and the process exit agree, and a run names what it ran.\n'
