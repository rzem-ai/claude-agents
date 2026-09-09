#!/usr/bin/env bash
#
# board-hook-contract.sh - hold the board hooks to the runtime's actual event
# shapes, and to the rule that a hook may move a card only on evidence.
#
# Every field asserted here was read out of the shipped CLI's own zod schemas
# rather than the docs pages, which truncate:
#
#   TaskCompleted   task_id, task_subject, task_description?, teammate_name?,
#                   team_name?                    (no task_title, no task_name)
#   SubagentStart   agent_id, agent_type          (no spawn prompt of any name)
#   SubagentStop    stop_hook_active, agent_id, agent_transcript_path,
#                   agent_type, last_assistant_message?, background_tasks?
#                                                 (no status, no completion_reason)
#
# Three of the fleet's hooks were reading fields from that "no" column. A hook
# that reads a field which does not exist does not fail loudly - it silently
# takes its fallback path forever, and the fallback looked like normal
# operation. These cases exist so that never goes unnoticed again.
#
# Usage:  evals/lib/board-hook-contract.sh [-v]
#
# Nothing here touches Notion: CLAUDE_AGENTS_BOARD=off, a throwaway config and
# state directory, and no token is ever loaded.

set -uo pipefail

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

LIB_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$LIB_DIR/../.." && pwd)
HOOKS="$REPO_ROOT/claude-agents/hooks"

command -v jq >/dev/null 2>&1 || {
    printf 'board-hook-contract: jq is needed to drive the hooks\n' >&2; exit 2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/board-hook-contract.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

export CLAUDE_AGENTS_CONFIG_DIR="$TMP/config"
export CLAUDE_AGENTS_STATE_DIR="$TMP/state"
export CLAUDE_AGENTS_BOARD=off
mkdir -p "$CLAUDE_AGENTS_CONFIG_DIR" "$CLAUDE_AGENTS_STATE_DIR"

PAGE_A=11111111111111111111111111111111
PAGE_B=22222222222222222222222222222222
# The hooks normalise to the hyphenated form before logging, so assertions match
# the resolved id rather than the text that happened to be in the task subject.
PAGE_A_H=11111111-1111-1111-1111-111111111111
PAGE_B_H=22222222-2222-2222-2222-222222222222

PASSED=0
FAILED=0

# run <hook> <json> -> writes exit code to $RC, hook log to $LOG
run_hook() {
    local hook="$1" json="$2"
    LOG="$TMP/log.$$"
    : > "$LOG"
    RC=0
    printf '%s' "$json" | BOARD_LOG_FILE="$LOG" "$HOOKS/$hook" >"$TMP/out" 2>"$TMP/err" || RC=$?
}

check() {
    # $1 case name, $2 description of the requirement, $3 predicate result (0 ok)
    if [ "$3" -eq 0 ]; then
        PASSED=$((PASSED + 1))
        printf '  ok    %-42s %s\n' "$1" "$2"
    else
        FAILED=$((FAILED + 1))
        printf '  FAIL  %-42s %s\n' "$1" "$2"
        if [ "$VERBOSE" -eq 1 ]; then
            printf '        exit=%s\n' "$RC"
            sed 's/^/        log: /' "$LOG" 2>/dev/null | head -10
        fi
    fi
}

log_has() { grep -qF "$1" "$LOG" 2>/dev/null; }

printf '\nTaskCompleted: the documented subject field\n'

# R05. The runtime sends task_subject. A marker in it must bind the item.
run_hook board-task-completed.sh \
    "$(jq -nc --arg s "Ship the refresh [board:$PAGE_A]" --arg c "$TMP" \
        '{session_id:"s1",cwd:$c,task_id:"t1",task_subject:$s}')"
log_has "names board item $PAGE_A_H"; check task_subject-binds "a [board:] marker in task_subject resolves the item" $?

# The legacy names stay readable, so an older build is not broken by the fix.
run_hook board-task-completed.sh \
    "$(jq -nc --arg s "Ship the refresh [board:$PAGE_A]" --arg c "$TMP" \
        '{session_id:"s1",cwd:$c,task_id:"t1",task_title:$s}')"
log_has "names board item $PAGE_A_H"; check task_title-fallback "the legacy task_title is still read as a fallback" $?

# Subject wins when both are present and disagree.
run_hook board-task-completed.sh \
    "$(jq -nc --arg a "Real [board:$PAGE_A]" --arg b "Stale [board:$PAGE_B]" --arg c "$TMP" \
        '{session_id:"s1",cwd:$c,task_id:"t1",task_subject:$a,task_title:$b}')"
log_has "names board item $PAGE_A_H" && ! log_has "$PAGE_B_H"; check subject-wins "task_subject wins over a conflicting task_title" $?

printf '\nTaskCompleted: only an explicit issue task closes an issue\n'

# R06. Bind two items in the session, then complete an unmarked task. Neither
# item may move: the old code picked whichever was touched most recently.
mkdir -p "$CLAUDE_AGENTS_STATE_DIR/sessions/s2"
printf '%s\n' "$PAGE_A" > "$CLAUDE_AGENTS_STATE_DIR/sessions/s2/last-item"
printf '%s\n' "$PAGE_B" > "$CLAUDE_AGENTS_STATE_DIR/sessions/s2/last-item"
run_hook board-task-completed.sh \
    "$(jq -nc --arg c "$TMP" '{session_id:"s2",cwd:$c,task_id:"t2",task_subject:"Fix the parser"}')"
! log_has "$PAGE_A_H" && ! log_has "$PAGE_B_H"; check unmarked-moves-nothing "an unmarked execution task moves no card" $?
log_has "no column moves"; check unmarked-explains "and says why, rather than failing silently" $?

# The environment binding must not close an issue either. It says which item is
# in flight, never that this task finished it.
run_hook board-task-completed.sh \
    "$(CLAUDE_AGENTS_BOARD_PAGE_ID=$PAGE_A jq -nc --arg c "$TMP" \
        '{session_id:"s3",cwd:$c,task_id:"t3",task_subject:"Partial work"}')"
! log_has "$PAGE_A_H"; check env-does-not-close "CLAUDE_AGENTS_BOARD_PAGE_ID alone does not close an issue" $?

printf '\nTaskCompleted: the gate tests the checkout that did the work\n'

# R03. Parent tree passes, worktree fails. The hook is told cwd=worktree and
# CLAUDE_PROJECT_DIR=parent, which is exactly what an isolated coder produces.
mkdir -p "$TMP/parent/.claude" "$TMP/worktree/.claude"
printf 'pass\n' > "$TMP/parent/.claude/test-status"
printf 'fail\nassertion failed in session.test.ts\n' > "$TMP/worktree/.claude/test-status"
RC=0
printf '%s' "$(jq -nc --arg c "$TMP/worktree" \
    '{session_id:"s4",cwd:$c,task_id:"t4",task_subject:"done"}')" \
    | CLAUDE_PROJECT_DIR="$TMP/parent" BOARD_LOG_FILE="$TMP/log.$$" \
      "$HOOKS/board-task-completed.sh" >"$TMP/out" 2>"$TMP/err" || RC=$?
LOG="$TMP/log.$$"
[ "$RC" -eq 2 ]; check worktree-is-tested "a failing worktree blocks even when the parent passes" $?

# R03, the other half: a pass that predates the code it approves is not evidence.
mkdir -p "$TMP/stale/.claude"
printf 'pass\n' > "$TMP/stale/.claude/test-status"
sleep 1
printf 'console.log("edited after the tests ran")\n' > "$TMP/stale/app.js"
run_hook board-task-completed.sh \
    "$(jq -nc --arg c "$TMP/stale" '{session_id:"s5",cwd:$c,task_id:"t5",task_subject:"done"}')"
log_has "has been modified since"; check stale-pass-ignored "a pass older than the tree is not treated as a pass" $?

# A fresh pass on an untouched tree still works, or the gate is just broken.
mkdir -p "$TMP/fresh/.claude"
printf 'console.log("code")\n' > "$TMP/fresh/app.js"
sleep 1
printf 'pass\n' > "$TMP/fresh/.claude/test-status"
run_hook board-task-completed.sh \
    "$(jq -nc --arg c "$TMP/fresh" '{session_id:"s6",cwd:$c,task_id:"t6",task_subject:"done"}')"
[ "$RC" -eq 0 ] && log_has "tests pass; moving to"; check fresh-pass-honoured "a pass newer than the tree is still honoured" $?

# A missing cwd means there is no checkout to verify, so it must refuse.
run_hook board-task-completed.sh \
    '{"session_id":"s7","cwd":"/nonexistent/nowhere","task_id":"t7","task_subject":"done"}'
[ "$RC" -eq 2 ]; check absent-cwd-blocks "an unusable cwd blocks rather than testing \$PWD" $?

printf '\nSubagentStart: binding without a spawn prompt\n'

# R07. The documented event carries agent identity only. With a session
# binding it must record the item; without one it must do nothing and say so.
run_hook board-subagent-start.sh \
    '{"session_id":"s8","agent_id":"a1","agent_type":"claude-agents:coder"}'
log_has "unbound"; check start-unbound-noop "a documented-shape start event with no binding moves nothing" $?

RC=0
printf '%s' '{"session_id":"s9","agent_id":"a2","agent_type":"claude-agents:coder"}' \
    | CLAUDE_AGENTS_BOARD_PAGE_ID="$PAGE_A" BOARD_LOG_FILE="$TMP/log.$$" \
      "$HOOKS/board-subagent-start.sh" >"$TMP/out" 2>"$TMP/err" || RC=$?
LOG="$TMP/log.$$"
log_has "picked up $PAGE_A_H"; check start-env-binds "an explicit session binding is recorded" $?

printf '\nSubagentStop: no status field exists\n'

# R15. The runtime sends no status, so the hook must not claim it saw one.
# This asserts the honest log line, not a behaviour change: the Blocked-on-
# failure path stays unreachable until the runtime emits something to reach it.
run_hook board-subagent-stop.sh \
    "$(jq -nc '{session_id:"s10",agent_id:"a3",agent_type:"claude-agents:scout",
                stop_hook_active:false,agent_transcript_path:"/dev/null",
                last_assistant_message:"## Done\n- x\n\n## Not done\n- none\n\n## Unverified\n- none\n\n## Decisions needed\n- none\n"}')"
log_has "no status field on SubagentStop"; check stop-status-honest "the hook records that no status field is sent" $?

printf '\nSubagentStop: a structured-output run carries no handoff\n'

# Measured against Claude Code 2.1.236 with a live probe, not read from docs: a
# subagent spawned from a workflow with a schema is forced through
# StructuredOutput, and its SubagentStop payload OMITS last_assistant_message
# entirely. Not JSON in that field, not an empty string - the key is absent.
#
# The hook read it as `// ""`, treated the absent status as success, and failed
# validate_handoff with "the final message is empty", exiting 2. Every workflow
# spawns fleet agents with schemas - scout and reviewer in review-round,
# researcher in deep-research, scout and spec-writer in spec-to-plan - and the
# SubagentStop matcher covers all nine fleet names, so the gate had been
# refusing to let those runs stop. Scoping the matcher (README item 12) fixed
# this for the built-in Plan and general-purpose lanes; it cannot help when the
# schema-carrying agent is itself a fleet agent.
#
# A run with no handoff field is not a malformed handoff. It is a run that was
# never asked for one.
run_hook board-subagent-stop.sh \
    "$(jq -nc '{session_id:"s11",agent_id:"a4",agent_type:"claude-agents:scout",
                stop_hook_active:false,agent_transcript_path:"/dev/null"}')"
[ "$RC" -eq 0 ]; check stop-structured-run-passes "a schema-spawned run with no handoff field is not a malformed handoff" $?

# The line the fix must not cross. A message that is present and empty is a
# fleet agent that was asked for a handoff and produced nothing, which is
# exactly what the gate exists to catch.
run_hook board-subagent-stop.sh \
    "$(jq -nc '{session_id:"s12",agent_id:"a5",agent_type:"claude-agents:scout",
                stop_hook_active:false,agent_transcript_path:"/dev/null",
                last_assistant_message:""}')"
[ "$RC" -eq 2 ]; check stop-empty-message-blocks "an empty final message is still a malformed handoff" $?

# And prose in place of the four headings stays refused, so the fix cannot be a
# blanket softening of the gate.
run_hook board-subagent-stop.sh \
    "$(jq -nc '{session_id:"s13",agent_id:"a6",agent_type:"claude-agents:scout",
                stop_hook_active:false,agent_transcript_path:"/dev/null",
                last_assistant_message:"I fixed it. Looks good to me."}')"
[ "$RC" -eq 2 ]; check stop-prose-blocks "prose in place of a handoff is still refused" $?

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    printf 'A board hook is reading a field the runtime does not send, or moving a card without evidence.\n'
    exit 1
fi
printf 'The board hooks match the runtime event shapes and move cards only on evidence.\n'
