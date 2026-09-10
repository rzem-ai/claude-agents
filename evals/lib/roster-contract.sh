#!/usr/bin/env bash
#
# roster-contract.sh - the roster agrees with itself.
#
# Adding an agent means editing twenty files, and the failure mode is not a
# broken one, it is a half-done one: a body with no eval directory, an eval
# directory the runner never runs, an agent the SubagentStop matcher does not
# name so its handoff is never checked. Each of those is silent.
#
# Every assertion here holds for the nine agents that existed before this file,
# so a failure means something new is incomplete rather than that the rules
# changed.
#
# Usage:  evals/lib/roster-contract.sh [-v]

set -uo pipefail

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

LIB_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$LIB_DIR/../.." && pwd)
AGENT_DIR="$REPO_ROOT/claude-agents/agents"
HOOKS_JSON="$REPO_ROOT/claude-agents/hooks/hooks.json"
RUN_SH="$REPO_ROOT/evals/run.sh"

PASSED=0
FAILED=0

check() {
    # $1 case name, $2 requirement, $3 predicate result (0 ok), $4 detail
    if [ "$3" -eq 0 ]; then
        PASSED=$((PASSED + 1))
        [ "$VERBOSE" -eq 1 ] && printf '  ok    %-34s %s\n' "$1" "$2"
    else
        FAILED=$((FAILED + 1))
        printf '  FAIL  %-34s %s\n' "$1" "$2"
        [ -n "${4:-}" ] && printf '        %s\n' "$4"
    fi
    return 0
}

WANT_SECTIONS='## Scope
## How you work
## Invariants
## Handoff'

# Space-flanked so membership below is an exact token match, not a substring
# match: \b treats a hyphen as a word boundary, so "writer" would match inside
# "spec-writer" even though it names no agent of its own.
ALL_AGENTS_LIST=" $(sed -n 's/^ALL_AGENTS="\(.*\)"/\1/p' "$RUN_SH") "

for body in "$AGENT_DIR"/*.md; do
    agent=$(basename "$body" .md)

    name=$(sed -n 's/^name: *//p' "$body" | head -1)
    [ "$name" = "$agent" ]
    check "$agent-name" "the name field matches the filename" $? "name: $name"

    lines=$(wc -l < "$body" | tr -d ' ')
    [ "$lines" -lt 60 ]
    check "$agent-length" "the body is under 60 lines" $? "$lines lines"

    got=$(grep '^## ' "$body")
    [ "$got" = "$WANT_SECTIONS" ]
    check "$agent-sections" "four H2 sections, in the contract's order" $? "$(printf '%s' "$got" | tr '\n' ' ')"

    ! grep -q '—\|–' "$body"
    check "$agent-dashes" "no em dashes and no en dashes" $?

    for skill in glossary handoff using-memory; do
        grep -q "^  - $skill\$" "$body"
        check "$agent-skill-$skill" "preloads $skill" $?
    done

    # [(|] on the left, because the first name in the alternation is preceded
    # by the opening bracket rather than a pipe - which `lead` is.
    grep -q "[(|]$agent[|)]" "$HOOKS_JSON"
    check "$agent-matcher" "is named in the SubagentStop matcher" $? "not in hooks.json"

    [ -d "$REPO_ROOT/evals/$agent" ]
    check "$agent-evals" "has an evals directory" $?

    case "$ALL_AGENTS_LIST" in
        *" $agent "*) true ;;
        *) false ;;
    esac
    check "$agent-runner" "is in the eval runner's ALL_AGENTS" $?
done

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    printf 'The roster disagrees with itself: an agent exists that some part of the fleet does not know about.\n'
    exit 1
fi
printf 'Every agent body, the matcher, the eval runner and the eval directories agree.\n'
