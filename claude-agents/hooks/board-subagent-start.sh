#!/usr/bin/env bash
# SubagentStart: move the board item into Doing and record which item this
# subagent is working on, so board-subagent-stop.sh and board-task-completed.sh
# can find it again.
#
# Fails soft, always. SubagentStart cannot block a spawn, and nothing about
# Notion is allowed to matter to the session.
set -euo pipefail

HOOK=SubagentStart
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/notion.sh
. "$HOOK_DIR/lib/notion.sh"

trap 'notion_tmp_cleanup' EXIT
trap 'board_log "$HOOK" "unexpected error on line $LINENO; session continues"; exit 0' ERR

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  board_log "$HOOK" "jq is not installed, so no hook input can be parsed. Install jq (macOS: brew install jq)."
  exit 0
fi

session_id="$(printf '%s' "$input" | jq -r '.session_id // ""')"
agent_id="$(printf '%s' "$input" | jq -r '.agent_id // ""')"
agent_type="$(printf '%s' "$input" | jq -r '.agent_type // ""')"
# The spawn prompt. Field name confirmed as `instructions`; the alternates are
# there because this is the one field the published schema does not show.
instructions="$(printf '%s' "$input" | jq -r '.instructions // .prompt // .initial_prompt // ""')"

page_id=""
source_of_id=""

if [ -n "$instructions" ]; then
  if page_id="$(page_id_from_instructions "$instructions")"; then
    source_of_id="Board-Item: line in the spawn prompt"
  else
    page_id=""
  fi
fi

if [ -z "$page_id" ] && [ -n "${CLAUDE_AGENTS_BOARD_PAGE_ID:-}" ]; then
  if page_id="$(normalise_page_id "$CLAUDE_AGENTS_BOARD_PAGE_ID")"; then
    source_of_id="CLAUDE_AGENTS_BOARD_PAGE_ID"
  else
    board_log "$HOOK" "CLAUDE_AGENTS_BOARD_PAGE_ID is set but is not a Notion page id or URL"
    page_id=""
  fi
fi

if [ -z "$page_id" ]; then
  board_log "$HOOK" "no board item for ${agent_type:-unknown agent} (${agent_id:-no id}): the spawn prompt carried no \"Board-Item:\" line and CLAUDE_AGENTS_BOARD_PAGE_ID is unset. Nothing moved. See hooks/README.md."
  exit 0
fi

if ! state_bind_agent "$session_id" "$agent_id" "$page_id" "$agent_type"; then
  board_log "$HOOK" "could not write the state file under $CLAUDE_AGENTS_STATE_DIR; later hooks will not find item $page_id"
fi

board_log "$HOOK" "${agent_type:-agent} ${agent_id:-} picked up $page_id (from the $source_of_id)"
board_write "$HOOK" "$page_id" "$BOARD_COL_DOING"

exit 0
