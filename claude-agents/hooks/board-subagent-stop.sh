#!/usr/bin/env bash
# SubagentStop: two jobs.
#
#   1. The board write. status failure or cancelled moves the item to Blocked.
#      status success with one or more "Blocker:" lines under Decisions needed
#      moves it to Blocked by human and attaches the blocker text as a comment.
#      A clean success changes no column - TaskCompleted owns Done.
#   2. The handoff-format check. On a successful run the final message must be
#      a valid handoff per skills/handoff/SKILL.md. If it is not, exit 2, which
#      stops the subagent stopping and hands the reason back to it.
#
# Every Notion failure is soft. The only thing that exits 2 here is a malformed
# handoff, and it exits 2 for that reason alone - never because Notion was
# unreachable.
set -euo pipefail

HOOK=SubagentStop
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/notion.sh
. "$HOOK_DIR/lib/notion.sh"

trap 'notion_tmp_cleanup' EXIT
trap 'board_log "$HOOK" "unexpected error on line $LINENO; session continues"; exit 0' ERR

# --------------------------------------------------------------- the validator
#
# Anchors quoted from skills/handoff/SKILL.md:
#   headings   ^## (Done|Not done|Unverified|Decisions needed)$
#   typed line ^- (Blocker|Propose item|Propose memory): 
# Items are "one markdown list item starting `- ` at column 0", an empty
# section is "exactly one line: `- None`", and the handoff is the last thing in
# the message.
RE_HANDOFF_HEADING='^## (Done|Not done|Unverified|Decisions needed)$'
RE_ANY_H2='^## '
RE_ITEM='^- '
RE_TYPED='^- (Blocker|Propose item|Propose memory): '
RE_NONE='^- None$'

HANDOFF_ERRORS=""

handoff_error() {
  HANDOFF_ERRORS="$HANDOFF_ERRORS
  - $1"
}

# validate_handoff MESSAGE -> 0 valid, 1 malformed (reasons in HANDOFF_ERRORS)
validate_handoff() {
  local msg="$1"
  local line sec="" order="" trunc
  local n_done=0 n_notdone=0 n_unver=0 n_dec=0
  local none_done=0 none_notdone=0 none_unver=0 none_dec=0
  HANDOFF_ERRORS=""

  if [ -z "$(printf '%s' "$msg" | tr -d '[:space:]')" ]; then
    handoff_error "the final message is empty, so it carries no handoff"
    return 1
  fi

  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ $line =~ $RE_ANY_H2 ]]; then
      if [[ $line =~ $RE_HANDOFF_HEADING ]]; then
        sec="${line#\#\# }"
        order="$order|$sec"
      else
        trunc="$(printf '%s' "$line" | cut -c1-60)"
        handoff_error "unexpected level-2 heading \"$trunc\". The handoff allows no other H2."
        sec=""
      fi
      continue
    fi
    [ -n "$sec" ] || continue
    if [ -z "$(printf '%s' "$line" | tr -d '[:space:]')" ]; then continue; fi

    if ! [[ $line =~ $RE_ITEM ]]; then
      trunc="$(printf '%s' "$line" | cut -c1-60)"
      handoff_error "line under \"## $sec\" does not start with \"- \" at column 0: \"$trunc\""
      continue
    fi

    case "$sec" in
      "Done")
        n_done=$((n_done + 1))
        if [[ $line =~ $RE_NONE ]]; then none_done=1; fi ;;
      "Not done")
        n_notdone=$((n_notdone + 1))
        if [[ $line =~ $RE_NONE ]]; then none_notdone=1; fi ;;
      "Unverified")
        n_unver=$((n_unver + 1))
        if [[ $line =~ $RE_NONE ]]; then none_unver=1; fi ;;
      "Decisions needed")
        n_dec=$((n_dec + 1))
        if [[ $line =~ $RE_NONE ]]; then
          none_dec=1
        elif ! [[ $line =~ $RE_TYPED ]]; then
          trunc="$(printf '%s' "$line" | cut -c1-60)"
          handoff_error "untyped line under \"## Decisions needed\": \"$trunc\". Every line there is \"- Blocker: \", \"- Propose item: \", \"- Propose memory: \" or the single line \"- None\"."
        fi
        ;;
    esac
  done <<< "$msg"

  if [ "$order" != "|Done|Not done|Unverified|Decisions needed" ]; then
    if [ -z "$order" ]; then
      handoff_error "no handoff headings found. The message must end with \"## Done\", \"## Not done\", \"## Unverified\" and \"## Decisions needed\", in that order."
    else
      handoff_error "headings are wrong. Found \"${order#|}\" (pipe separated); expected exactly \"Done|Not done|Unverified|Decisions needed\", each once, in that order."
    fi
  fi

  if [ "$n_done" -eq 0 ];    then handoff_error "\"## Done\" is empty. An empty section is exactly one line: \"- None\"."; fi
  if [ "$n_notdone" -eq 0 ]; then handoff_error "\"## Not done\" is empty. An empty section is exactly one line: \"- None\"."; fi
  if [ "$n_unver" -eq 0 ];   then handoff_error "\"## Unverified\" is empty. An empty section is exactly one line: \"- None\"."; fi
  if [ "$n_dec" -eq 0 ];     then handoff_error "\"## Decisions needed\" is empty. An empty section is exactly one line: \"- None\"."; fi

  if [ "$none_done" -eq 1 ]    && [ "$n_done" -gt 1 ];    then handoff_error "\"## Done\" mixes \"- None\" with real items. \"- None\" is only ever the whole section."; fi
  if [ "$none_notdone" -eq 1 ] && [ "$n_notdone" -gt 1 ]; then handoff_error "\"## Not done\" mixes \"- None\" with real items. \"- None\" is only ever the whole section."; fi
  if [ "$none_unver" -eq 1 ]   && [ "$n_unver" -gt 1 ];   then handoff_error "\"## Unverified\" mixes \"- None\" with real items. \"- None\" is only ever the whole section."; fi
  if [ "$none_dec" -eq 1 ]     && [ "$n_dec" -gt 1 ];     then handoff_error "\"## Decisions needed\" mixes \"- None\" with real items. \"- None\" is only ever the whole section."; fi

  [ -z "$HANDOFF_ERRORS" ]
}

# extract_blockers MESSAGE -> the text of each "- Blocker: " line, one per line.
# Scoped to the Decisions needed section rather than the whole message, so a
# Blocker line that drifted into Done is caught by the validator instead of
# quietly parking a false alarm in the human queue.
extract_blockers() {
  printf '%s\n' "$1" \
    | tr -d '\r' \
    | awk '/^## Decisions needed$/ {inside=1; next} /^## / {inside=0} inside' \
    | grep -E '^- Blocker: ' \
    | sed -E 's/^- Blocker:[[:space:]]*//' \
    || true
}

# ------------------------------------------------------------------- the hook

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  board_log "$HOOK" "jq is not installed, so neither the board write nor the handoff check can run. Install jq (macOS: brew install jq)."
  exit 0
fi

session_id="$(printf '%s' "$input" | jq -r '.session_id // ""')"
agent_id="$(printf '%s' "$input" | jq -r '.agent_id // ""')"
agent_type="$(printf '%s' "$input" | jq -r '.agent_type // ""')"
message="$(printf '%s' "$input" | jq -r '.last_assistant_message // ""')"
# `status` is the documented field. `completion_reason` is read as a fallback
# because the published example block spells it that way; see README.
status_raw="$(printf '%s' "$input" | jq -r '.status // .completion_reason // ""')"

case "$(printf '%s' "$status_raw" | tr 'A-Z' 'a-z')" in
  success|succeeded|ok|completed) status=success ;;
  failure|failed|error)            status=failure ;;
  cancelled|canceled|user_interrupt|interrupted) status=cancelled ;;
  "") status=success
      board_log "$HOOK" "no status field on the hook input; treating the run as a success" ;;
  *)  status=success
      board_log "$HOOK" "unrecognised status \"$status_raw\"; treating the run as a success" ;;
esac

page_id=""
if page_id="$(state_agent_page_id "$session_id" "$agent_id")"; then
  :
elif [ -n "${CLAUDE_AGENTS_BOARD_PAGE_ID:-}" ] && page_id="$(normalise_page_id "$CLAUDE_AGENTS_BOARD_PAGE_ID")"; then
  board_log "$HOOK" "no state file for ${agent_id:-no id}; falling back to CLAUDE_AGENTS_BOARD_PAGE_ID"
else
  page_id=""
  board_log "$HOOK" "no board item bound to ${agent_type:-agent} ${agent_id:-no id}; the column will not change"
fi

# 1. A failed or cancelled run goes to Blocked, and that is the end of it. The
#    handoff check deliberately does not run here: exit 2 would refuse to let a
#    cancelled subagent stop, which is the opposite of what a cancellation means.
if [ "$status" = "failure" ] || [ "$status" = "cancelled" ]; then
  board_log "$HOOK" "${agent_type:-agent} finished with status $status"
  board_write "$HOOK" "$page_id" "$BOARD_COL_BLOCKED"
  exit 0
fi

# 2. Successful run: the handoff must parse before anything is trusted from it.
if ! validate_handoff "$message"; then
  trap - ERR
  {
    printf 'Your final message is not a valid handoff, so the board could not be updated from it.\n'
    printf 'The handoff is a machine contract - see the `handoff` skill. Problems found:\n'
    printf '%s\n\n' "$HANDOFF_ERRORS"
    printf 'Reply with the same content, ending in exactly these four headings in this order,\n'
    printf 'each with at least one "- " item at column 0, and "- None" alone where a section is empty:\n\n'
    printf '## Done\n## Not done\n## Unverified\n## Decisions needed\n'
  } >&2
  board_log "$HOOK" "handoff from ${agent_type:-agent} is malformed; exit 2 to make it re-emit"
  exit 2
fi

blockers="$(extract_blockers "$message")"

if [ -n "$blockers" ]; then
  count="$(printf '%s\n' "$blockers" | grep -c . || true)"
  comment="$(printf '%s\n' \
    "Blocked by human. ${agent_type:-A subagent} raised ${count} blocker(s) in its handoff:" \
    "" \
    "$(printf '%s\n' "$blockers" | sed 's/^/- /')")"
  board_log "$HOOK" "${count} blocker(s) from ${agent_type:-agent}; moving to \"$BOARD_COL_BLOCKED_HUMAN\""
  board_write "$HOOK" "$page_id" "$BOARD_COL_BLOCKED_HUMAN" "$comment"
else
  board_log "$HOOK" "${agent_type:-agent} succeeded with no blockers; leaving the column alone for TaskCompleted"
fi

exit 0
