#!/usr/bin/env bash
# TaskCompleted: one hook, two outcomes.
#
#   tests pass -> move the board item to Done, exit 0.
#   tests fail -> move the board item to Blocked with a comment saying the test
#                 gate failed and how, then exit 2 so the task cannot be marked
#                 complete.
#
# The comment takes the same shape as the ones board-subagent-stop.sh posts: a
# headline naming the transition and its source, then the detail underneath. This
# hook never sees a handoff - it has the task title, the test command or the
# marker file, and the output - so the comment says only those things.
#
# The board write happens on both paths, and it happens before the exit, so the
# gate firing never costs the board its update. Notion being unreachable never
# changes the verdict: the exit 2 is about the tests and nothing else.
#
# "Tests pass" is not something the harness tells us, so it is resolved in
# order: a configured test command, then a test-status marker file, then the
# gate mode. See hooks/README.md, "The test gate".
set -euo pipefail

HOOK=TaskCompleted
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/notion.sh
. "$HOOK_DIR/lib/notion.sh"

trap 'notion_tmp_cleanup' EXIT
trap 'board_log "$HOOK" "unexpected error on line $LINENO; task allowed through"; exit 0' ERR

CLAUDE_AGENTS_TEST_GATE="${CLAUDE_AGENTS_TEST_GATE:-lenient}"
CLAUDE_AGENTS_TEST_COMMAND="${CLAUDE_AGENTS_TEST_COMMAND:-}"
CLAUDE_AGENTS_TEST_TIMEOUT="${CLAUDE_AGENTS_TEST_TIMEOUT:-300}"
CLAUDE_AGENTS_TEST_STATUS_MAX_AGE="${CLAUDE_AGENTS_TEST_STATUS_MAX_AGE:-3600}"

file_mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || printf '0'
}

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  board_log "$HOOK" "jq is not installed, so the test gate cannot run. Task allowed through. Install jq (macOS: brew install jq)."
  exit 0
fi

session_id="$(printf '%s' "$input" | jq -r '.session_id // ""')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // ""')"
task_id="$(printf '%s' "$input" | jq -r '.task_id // ""')"
# `task_title` is the documented field; `task_name` is read as a fallback
# because the published example block spells it that way. See README.
task_title="$(printf '%s' "$input" | jq -r '.task_title // .task_name // ""')"

work_dir="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -d "$work_dir" ] || work_dir="$PWD"

# ------------------------------------------------------------ the board item
#
# Native tasks are not board items - most of them should resolve to nothing at
# all, and that is correct rather than a failure. Only a task whose title
# carries a [board:<id>] marker, or a session with exactly one item in flight,
# moves a column.
page_id=""
if page_id="$(page_id_from_task_title "$task_title")"; then
  board_log "$HOOK" "task \"$task_title\" names board item $page_id"
elif page_id="$(state_session_page_id "$session_id")"; then
  board_log "$HOOK" "no [board:...] marker on the task; using the item most recently picked up in this session ($page_id)"
elif [ -n "${CLAUDE_AGENTS_BOARD_PAGE_ID:-}" ] && page_id="$(normalise_page_id "$CLAUDE_AGENTS_BOARD_PAGE_ID")"; then
  board_log "$HOOK" "using CLAUDE_AGENTS_BOARD_PAGE_ID ($page_id)"
else
  page_id=""
  board_log "$HOOK" "no board item resolves for task ${task_id:-unknown}; the gate still runs, no column moves"
fi

# --------------------------------------------------------------- the verdict
verdict=""        # pass | fail | unknown
detail=""

if [ -n "$CLAUDE_AGENTS_TEST_COMMAND" ]; then
  runner=""
  if [ "$CLAUDE_AGENTS_TEST_TIMEOUT" -gt 0 ] 2>/dev/null; then
    if command -v timeout >/dev/null 2>&1; then
      runner="timeout $CLAUDE_AGENTS_TEST_TIMEOUT"
    elif command -v gtimeout >/dev/null 2>&1; then
      runner="gtimeout $CLAUDE_AGENTS_TEST_TIMEOUT"
    fi
  fi
  board_log "$HOOK" "running the test command in $work_dir: $CLAUDE_AGENTS_TEST_COMMAND"
  # Run it as the condition of an if, not after `set +e`: the ERR trap fires on
  # any failing command regardless of errexit, and a failing test suite is the
  # expected case here, not an unexpected error.
  # bash -c, not eval of "$runner $CMD": prefixing timeout as text onto the
  # command breaks anything compound. "cd app && npm test" became
  # "timeout 300 cd app && npm test", which fails on `timeout cd` and never
  # runs the suite - and the gate then blocks the task for tests that were
  # never executed. Running the command as one shell string keeps pipelines,
  # && chains and loops working, with or without timeout present.
  if out="$(cd "$work_dir" && $runner bash -c "$CLAUDE_AGENTS_TEST_COMMAND" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    verdict=pass
    detail="\`$CLAUDE_AGENTS_TEST_COMMAND\` passed."
  else
    verdict=fail
    detail="$(printf '`%s` exited %s.\n\nLast lines of output:\n\n%s' \
      "$CLAUDE_AGENTS_TEST_COMMAND" "$rc" "$(printf '%s\n' "$out" | tail -15 | cut -c1-200)")"
  fi
fi

status_file="${CLAUDE_AGENTS_TEST_STATUS_FILE:-$work_dir/.claude/test-status}"
if [ -z "$verdict" ] && [ -f "$status_file" ]; then
  age=$(( $(date +%s) - $(file_mtime "$status_file") ))
  word="$(head -1 "$status_file" | tr -d '\r' | awk '{print tolower($1)}')"
  if [ "$age" -gt "$CLAUDE_AGENTS_TEST_STATUS_MAX_AGE" ]; then
    board_log "$HOOK" "$status_file says \"$word\" but is ${age}s old (limit ${CLAUDE_AGENTS_TEST_STATUS_MAX_AGE}s); treating it as stale"
  else
    case "$word" in
      pass|passed|ok|green)
        verdict=pass; detail="$status_file reports a pass." ;;
      fail|failed|red)
        verdict=fail
        detail="$(printf '%s reports a failure.\n\n%s' "$status_file" "$(sed -n '2,16p' "$status_file" | cut -c1-200)")" ;;
      *)
        board_log "$HOOK" "$status_file does not start with pass or fail (found \"$word\"); ignoring it" ;;
    esac
  fi
fi

if [ -z "$verdict" ]; then
  verdict=unknown
fi

# Which run this was, for the archive a cut comment points at. This hook's own
# comment is bounded well under the cap - the test detail is at most fifteen
# lines cut to 200 characters each - so it should never be the one that cuts.
# It can be if board.env lowers NOTION_COMMENT_MAX_CHARS, and the archiving
# lives in notion_comment either way, so all this hook owes it is a label.
BOARD_RUN_SESSION="$session_id"
BOARD_RUN_STATUS="test gate: $verdict"

# ---------------------------------------------------------------- the outcome
case "$verdict" in
  pass)
    board_log "$HOOK" "tests pass; moving to \"$BOARD_COL_DONE\""
    board_write "$HOOK" "$page_id" "$BOARD_COL_DONE"
    exit 0
    ;;
  fail)
    board_log "$HOOK" "tests failed; moving to \"$BOARD_COL_BLOCKED\" and blocking completion"
    headline="Blocked. The test gate failed, so the task could not be marked complete."
    if [ -n "$task_title" ]; then
      headline="Blocked. The test gate failed on \"$(printf '%s' "$task_title" | cut -c1-120)\", so the task could not be marked complete."
    fi
    comment="$(printf '%s\n\n%s\n' "$headline" "$detail")"
    # The write happens first, so the exit below cannot skip it.
    board_write "$HOOK" "$page_id" "$BOARD_COL_BLOCKED" "$comment"
    trap - ERR
    {
      printf 'Tests are not passing, so this task cannot be marked complete.\n\n'
      printf '%s\n\n' "$detail"
      printf 'Fix the failures and complete the task again. The board item is in "%s".\n' "$BOARD_COL_BLOCKED"
    } >&2
    exit 2
    ;;
  *)
    if [ "$CLAUDE_AGENTS_TEST_GATE" = "strict" ]; then
      board_log "$HOOK" "no test result available and the gate is strict; blocking completion"
      board_write "$HOOK" "$page_id" "$BOARD_COL_BLOCKED" "$(printf '%s\n\n%s\n' \
        "Blocked. The test gate failed, so the task could not be marked complete." \
        "No test result was available and CLAUDE_AGENTS_TEST_GATE is strict. Set CLAUDE_AGENTS_TEST_COMMAND, or write the result to $status_file with pass or fail on the first line.")"
      trap - ERR
      {
        printf 'No test result was available and CLAUDE_AGENTS_TEST_GATE is strict, so this task\n'
        printf 'cannot be marked complete. Run the tests and write the result to %s\n' "$status_file"
        printf '(first line "pass" or "fail"), or set CLAUDE_AGENTS_TEST_COMMAND. See hooks/README.md.\n'
      } >&2
      exit 2
    fi
    board_log "$HOOK" "no test gate configured (no CLAUDE_AGENTS_TEST_COMMAND, no usable $status_file); moving to \"$BOARD_COL_DONE\" ungated. Set CLAUDE_AGENTS_TEST_GATE=strict to refuse instead."
    board_write "$HOOK" "$page_id" "$BOARD_COL_DONE"
    exit 0
    ;;
esac
