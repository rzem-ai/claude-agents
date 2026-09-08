# shellcheck shell=bash
# Shared helpers for the board hooks. Sourced, never executed.
#
# Everything here is written for bash 3.2, because that is what /bin/bash is on
# macOS: no associative arrays, no ${var,,}, no mapfile, no globstar.
#
# The token never reaches a command line. curl is driven from a --config file
# written under a 0700 temp directory, so the Authorization header never appears
# in `ps` output and never lands in a log.

# Tracing would print the token. Refuse to run traced, and turn it off anyway.
set +x

CLAUDE_AGENTS_CONFIG_DIR="${CLAUDE_AGENTS_CONFIG_DIR:-$HOME/.config/claude-agents}"
CLAUDE_AGENTS_TOKEN_FILE="${CLAUDE_AGENTS_TOKEN_FILE:-$CLAUDE_AGENTS_CONFIG_DIR/notion.token}"
CLAUDE_AGENTS_STATE_DIR="${CLAUDE_AGENTS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-agents}"

# Defaults for everything the plan did not name. board.env overrides them.
NOTION_API="${NOTION_API:-https://api.notion.com}"
NOTION_VERSION="${NOTION_VERSION:-2022-06-28}"
BOARD_STATUS_PROPERTY="${BOARD_STATUS_PROPERTY:-Status}"
BOARD_STATUS_TYPE="${BOARD_STATUS_TYPE:-status}"
BOARD_COL_TODO="${BOARD_COL_TODO:-To do}"
BOARD_COL_DOING="${BOARD_COL_DOING:-Doing}"
BOARD_COL_BLOCKED="${BOARD_COL_BLOCKED:-Blocked}"
BOARD_COL_BLOCKED_HUMAN="${BOARD_COL_BLOCKED_HUMAN:-Blocked by human}"
BOARD_COL_DONE="${BOARD_COL_DONE:-Done}"

# How much of a comment reaches the card. See notion_comment for why there is a
# cap at all and why this number is nowhere near Notion's own ceiling.
NOTION_COMMENT_MAX_CHARS="${NOTION_COMMENT_MAX_CHARS:-8000}"

# Which run a comment belongs to. A hook sets these before it calls board_write
# or board_comment, and the only thing that reads them is the archive a cut
# comment points at, so a hook that sets none of them still works and just gets
# an archive labelled "not recorded". Nothing here is secret and nothing here is
# ever the token.
BOARD_RUN_SESSION="${BOARD_RUN_SESSION:-}"
BOARD_RUN_AGENT="${BOARD_RUN_AGENT:-}"
BOARD_RUN_AGENT_ID="${BOARD_RUN_AGENT_ID:-}"
BOARD_RUN_STATUS="${BOARD_RUN_STATUS:-}"

# board.env is optional. It lives in the 0700 config directory that
# permissions.deny already hides from every agent, so sourcing it is no wider a
# hole than the token file sitting next to it.
if [ -f "$CLAUDE_AGENTS_CONFIG_DIR/board.env" ]; then
  # shellcheck disable=SC1091
  . "$CLAUDE_AGENTS_CONFIG_DIR/board.env"
fi

BOARD_LOG_FILE="${BOARD_LOG_FILE:-$CLAUDE_AGENTS_STATE_DIR/log/hooks.log}"

board_log() {
  # $1 hook name, rest message. stderr for the transcript, file for later.
  local hook="$1"; shift
  local line
  line="$(date -u '+%Y-%m-%dT%H:%M:%SZ') [$hook] $*"
  printf '%s\n' "$line" >&2
  if mkdir -p "$(dirname "$BOARD_LOG_FILE")" 2>/dev/null; then
    printf '%s\n' "$line" >> "$BOARD_LOG_FILE" 2>/dev/null || true
  fi
}

# A board write must never break the session. Callers use this for anything
# that is only about Notion.
board_soft_fail() {
  board_log "$1" "board write skipped: $2"
  return 1
}

board_disabled() {
  if [ "${CLAUDE_AGENTS_BOARD:-on}" = "off" ]; then return 0; fi
  if [ -f "$CLAUDE_AGENTS_STATE_DIR/disabled" ]; then return 0; fi
  return 1
}

require_tools() {
  local hook="$1" missing=""
  command -v curl >/dev/null 2>&1 || missing="$missing curl"
  command -v jq >/dev/null 2>&1 || missing="$missing jq"
  if [ -n "$missing" ]; then
    board_log "$hook" "missing required tool(s):$missing. Install them (macOS: brew install jq) or the board hooks cannot run. Session continues."
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------- state files
#
# The state directory is how a later hook finds the board item a subagent was
# spawned against. See README, "Which board item".

state_session_dir() {
  # $1 session_id
  local sid="${1:-unknown-session}"
  sid="$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_')"
  printf '%s/sessions/%s' "$CLAUDE_AGENTS_STATE_DIR" "$sid"
}

state_bind_agent() {
  # $1 session_id, $2 agent_id, $3 page_id, $4 agent_type
  local dir; dir="$(state_session_dir "$1")"
  local aid; aid="$(printf '%s' "${2:-unknown-agent}" | tr -c 'A-Za-z0-9._-' '_')"
  local old_umask; old_umask="$(umask)"
  umask 077
  mkdir -p "$dir/agents" 2>/dev/null || { umask "$old_umask"; return 1; }
  {
    printf 'page_id=%s\n' "$3"
    printf 'agent_type=%s\n' "$4"
    printf 'bound_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "$dir/agents/$aid" 2>/dev/null || { umask "$old_umask"; return 1; }
  # Session-level pointer: the item most recently picked up in this session.
  # TaskCompleted has no agent_id, so this is its last resort.
  printf '%s\n' "$3" > "$dir/last-item" 2>/dev/null || true
  umask "$old_umask"
  return 0
}

state_agent_page_id() {
  # $1 session_id, $2 agent_id
  local dir; dir="$(state_session_dir "$1")"
  local aid; aid="$(printf '%s' "${2:-unknown-agent}" | tr -c 'A-Za-z0-9._-' '_')"
  [ -f "$dir/agents/$aid" ] || return 1
  local v
  v="$(sed -n 's/^page_id=//p' "$dir/agents/$aid" | head -1)"
  [ -n "$v" ] || return 1
  printf '%s\n' "$v"
}

state_session_page_id() {
  local dir; dir="$(state_session_dir "$1")"
  [ -f "$dir/last-item" ] || return 1
  local v; v="$(head -1 "$dir/last-item")"
  [ -n "$v" ] || return 1
  printf '%s\n' "$v"
}

# ---------------------------------------------------------------- run archives
#
# Where the overflow of a cut comment goes. A comment too long for a card is cut,
# and the note on the end of it names a file written here. Before this existed
# the note pointed at a "run transcript" that nothing anywhere writes, so the one
# message telling Alex there was more to read pointed at nothing, on exactly the
# runs with the most to say.
#
# The archive goes in the state directory and never in the hook's cwd. The coder
# runs with isolation: worktree, so its cwd is a git worktree under
# .claude/worktrees/ that goes away with the session - an archive written there
# would vanish with the thing it exists to outlive.
#
# Layout, one file per cut comment:
#
#   archives/<session_id>/<UTC timestamp>-<agent, or the hook if there is none>.md
#
# Session first, because a session id is what a person has in hand when they come
# back to a run; agent and timestamp in the name, because that is what tells two
# cut comments in one session apart without opening either. Nothing prunes them.

board_archive_dir() {
  local sid
  sid="$(printf '%s' "${BOARD_RUN_SESSION:-}" | tr -c 'A-Za-z0-9._-' '_')"
  [ -n "$sid" ] || sid="unknown-session"
  printf '%s/archives/%s' "$CLAUDE_AGENTS_STATE_DIR" "$sid"
}

# board_archive_comment HOOK PAGE_ID TEXT
# Writes the full comment text with a header saying which run it came from, and
# echoes the path it wrote. Returns 1, having logged why, if anything failed:
# an archive that could not be written is not a reason to lose the card comment
# as well, so the caller carries on and posts the cut text.
board_archive_comment() {
  local hook="$1" page="$2" text="$3"
  local dir file stamp name hex url n old_umask

  dir="$(board_archive_dir)"
  stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  name="$(printf '%s' "${BOARD_RUN_AGENT:-}" | tr -c 'A-Za-z0-9._-' '_')"
  [ -n "$name" ] || name="$hook"
  file="$dir/$stamp-$name.md"
  n=2
  while [ -e "$file" ] && [ "$n" -lt 100 ]; do
    file="$dir/$stamp-$name-$n.md"
    n=$((n + 1))
  done

  hex="$(printf '%s' "$page" | tr -cd '0-9a-fA-F')"
  url=""
  if [ -n "$hex" ]; then url="https://www.notion.so/$hex"; fi

  # Same discipline as the session state files: 0700 on the directory, 0600 on
  # the file. Nothing in here is secret, and nothing in here is anyone else's
  # business either.
  old_umask="$(umask)"
  umask 077
  if ! mkdir -p "$dir" 2>/dev/null; then
    umask "$old_umask"
    board_log "$hook" "could not create the archive directory $dir; the full text of this comment is saved nowhere"
    return 1
  fi
  {
    printf '# Board comment archive\n\n'
    printf -- '- Written: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf -- '- Hook: %s\n' "$hook"
    printf -- '- Agent: %s%s\n' "${BOARD_RUN_AGENT:-not recorded}" "${BOARD_RUN_AGENT_ID:+ ($BOARD_RUN_AGENT_ID)}"
    printf -- '- Status: %s\n' "${BOARD_RUN_STATUS:-not recorded}"
    printf -- '- Session: %s\n' "${BOARD_RUN_SESSION:-not recorded}"
    printf -- '- Board item: %s%s\n' "${page:-not resolved}" "${url:+ ($url)}"
    printf '\n'
    printf 'The comment on the card was cut to fit Notion. This is the whole of it.\n\n'
    printf '## Full comment text\n\n'
    printf '%s\n' "$text"
  } > "$file" 2>/dev/null || {
    umask "$old_umask"
    board_log "$hook" "could not write the archive $file; the full text of this comment is saved nowhere"
    return 1
  }
  umask "$old_umask"
  printf '%s\n' "$file"
  return 0
}

# ------------------------------------------------------------- page id parsing

# Accepts a bare id (dashed or not) or any notion.so URL and returns the
# canonical dashed UUID. The id is always the last 32 hex characters of a Notion
# URL, which is why the query string and fragment come off first.
normalise_page_id() {
  local raw="$1" hex len
  raw="$(printf '%s' "$raw" | tr -d '\r' | sed -e 's/[?#].*$//' -e 's/[[:space:]]*$//')"
  hex="$(printf '%s' "$raw" | tr -cd '0-9a-fA-F')"
  len=${#hex}
  [ "$len" -ge 32 ] || return 1
  hex="$(printf '%s' "$hex" | tail -c 32)"
  hex="$(printf '%s' "$hex" | tr 'A-F' 'a-f')"
  printf '%s-%s-%s-%s-%s\n' \
    "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}"
}

# The spawn-prompt convention. One line anywhere in the instructions:
#   Board-Item: 24f1a3b9c1d24e6f8a0b1c2d3e4f5061
# or the page URL. Leading "- " and any case are tolerated; nothing else is.
page_id_from_instructions() {
  local text="$1" line
  line="$(printf '%s' "$text" | tr -d '\r' \
    | grep -Ei -m1 '^[[:space:]]*(-[[:space:]]+)?board-item:[[:space:]]*[^[:space:]]+' || true)"
  [ -n "$line" ] || return 1
  line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*(-[[:space:]]+)?[Bb][Oo][Aa][Rr][Dd]-[Ii][Tt][Ee][Mm]:[[:space:]]*//' \
    | awk '{print $1}')"
  normalise_page_id "$line"
}

# The task-title convention, for TaskCompleted: a marker anywhere in the title.
#   Wire up refresh rotation [board:24f1a3b9c1d24e6f8a0b1c2d3e4f5061]
page_id_from_task_title() {
  local text="$1" id
  id="$(printf '%s' "$text" | grep -Eio '\[board:[^]]+\]' | head -1 || true)"
  [ -n "$id" ] || return 1
  id="$(printf '%s' "$id" | sed -E 's/^\[[Bb][Oo][Aa][Rr][Dd]:[[:space:]]*//; s/[[:space:]]*\]$//')"
  normalise_page_id "$id"
}

# ------------------------------------------------------------------ Notion API

notion_tmp_init() {
  # $1 hook name. Sets NOTION_TMP and arranges its removal.
  local hook="$1"
  umask 077
  NOTION_TMP="$(mktemp -d "${TMPDIR:-/tmp}/claude-agents-$hook.XXXXXX" 2>/dev/null)" || return 1
  chmod 700 "$NOTION_TMP" 2>/dev/null || true
  return 0
}

notion_tmp_cleanup() {
  if [ -n "${NOTION_TMP:-}" ] && [ -d "$NOTION_TMP" ]; then rm -rf "$NOTION_TMP"; fi
  return 0
}

# Reads the token into NOTION_TOKEN. Never printed, never exported, never
# passed to op. The file is rendered once by scripts/install-home.sh.
notion_load_token() {
  local hook="$1"
  if [ ! -f "$CLAUDE_AGENTS_TOKEN_FILE" ]; then
    board_log "$hook" "no token at $CLAUDE_AGENTS_TOKEN_FILE - run scripts/install-home.sh. Board not updated."
    return 1
  fi
  if [ ! -r "$CLAUDE_AGENTS_TOKEN_FILE" ]; then
    board_log "$hook" "token file exists but is not readable by this user. Board not updated."
    return 1
  fi
  # GNU stat and BSD stat disagree on both the flag and its meaning: -f is
  # "format" on GNU but "filesystem" on BSD, so GNU is tried first and the
  # answer is sanity-checked before it is believed.
  local mode
  mode="$(stat -c '%a' "$CLAUDE_AGENTS_TOKEN_FILE" 2>/dev/null || true)"
  case "$mode" in
    [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) : ;;
    *) mode="$(stat -f '%Lp' "$CLAUDE_AGENTS_TOKEN_FILE" 2>/dev/null || true)" ;;
  esac
  case "$mode" in
    600|400|0600|0400) : ;;
    [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7])
      board_log "$hook" "token file mode is $mode, expected 600. Fix with chmod 600 on that file." ;;
    *) board_log "$hook" "could not read the token file mode; continuing" ;;
  esac
  NOTION_TOKEN="$(tr -d '\r\n' < "$CLAUDE_AGENTS_TOKEN_FILE")"
  if [ -z "$NOTION_TOKEN" ]; then
    board_log "$hook" "token file is empty. Board not updated."
    return 1
  fi
  return 0
}

# notion_api METHOD URL [BODY_FILE]
# Echoes the HTTP status. Response body lands in $NOTION_TMP/response.json.
notion_api() {
  local method="$1" url="$2" body="${3:-}"
  local cfg="$NOTION_TMP/curl.cfg"
  local resp="$NOTION_TMP/response.json"
  local code
  : > "$cfg"; chmod 600 "$cfg"
  {
    printf 'url = "%s"\n' "$url"
    printf 'request = "%s"\n' "$method"
    printf 'header = "Authorization: Bearer %s"\n' "$NOTION_TOKEN"
    printf 'header = "Notion-Version: %s"\n' "$NOTION_VERSION"
    printf 'header = "Content-Type: application/json"\n'
    printf 'silent\n'
    printf 'show-error\n'
    printf 'connect-timeout = 5\n'
    printf 'max-time = 12\n'
    printf 'retry = 1\n'
    printf 'output = "%s"\n' "$resp"
    printf 'write-out = "%%{http_code}"\n'
    if [ -n "$body" ]; then printf 'data = "@%s"\n' "$body"; fi
  } > "$cfg"
  code="$(curl --config "$cfg" 2>"$NOTION_TMP/curl.err")" || code=""
  rm -f "$cfg"
  [ -n "$code" ] || code="000"
  printf '%s\n' "$code"
}

# The API error message, with anything token-shaped removed. Notion never
# echoes the token back, but a proxy in the middle might.
notion_error_text() {
  local resp="$NOTION_TMP/response.json"
  local msg=""
  if [ -s "$resp" ]; then
    msg="$(jq -r '(.message // .code // empty)' "$resp" 2>/dev/null || true)"
  fi
  if [ -z "$msg" ] && [ -s "$NOTION_TMP/curl.err" ]; then
    msg="$(head -c 300 "$NOTION_TMP/curl.err")"
  fi
  printf '%s' "${msg:-no detail}" | sed -E 's/(secret|ntn)_[A-Za-z0-9]+/[redacted]/g'
}

# notion_set_status HOOK PAGE_ID COLUMN
# Tries the configured property type, then the other one once, because a board
# view can be built on either a status property or a select property and the
# PATCH body differs between them.
notion_set_status() {
  local hook="$1" page="$2" col="$3"
  local url="$NOTION_API/v1/pages/$page"
  local body="$NOTION_TMP/status.json"
  local type="$BOARD_STATUS_TYPE" other code

  if [ "$type" = "status" ]; then other="select"; else other="status"; fi

  if board_disabled; then
    board_log "$hook" "board writes disabled; would set $BOARD_STATUS_PROPERTY=$col on $page"
    return 0
  fi
  if [ -n "${BOARD_DRY_RUN:-}" ]; then
    board_log "$hook" "dry run: PATCH $page $BOARD_STATUS_PROPERTY=$col"
    return 0
  fi

  jq -n --arg p "$BOARD_STATUS_PROPERTY" --arg v "$col" --arg t "$type" \
    '{properties: {($p): ({} | .[$t] = {name: $v})}}' > "$body" 2>/dev/null \
    || { board_log "$hook" "could not build the status body"; return 1; }
  code="$(notion_api PATCH "$url" "$body")"
  if [ "$code" = "200" ]; then
    board_log "$hook" "moved $page to \"$col\""
    return 0
  fi

  if [ "$code" = "400" ]; then
    board_log "$hook" "PATCH as a $type property returned 400 ($(notion_error_text)); retrying as $other"
    jq -n --arg p "$BOARD_STATUS_PROPERTY" --arg v "$col" --arg t "$other" \
      '{properties: {($p): ({} | .[$t] = {name: $v})}}' > "$body" 2>/dev/null || return 1
    code="$(notion_api PATCH "$url" "$body")"
    if [ "$code" = "200" ]; then
      board_log "$hook" "moved $page to \"$col\" (property is a $other, not a $type - set BOARD_STATUS_TYPE=$other in board.env)"
      return 0
    fi
  fi

  board_log "$hook" "HTTP $code moving $page to \"$col\": $(notion_error_text)"
  return 1
}

# notion_comment HOOK PAGE_ID TEXT
#
# The limits are Notion's, from https://developers.notion.com/reference/request-limits:
# one rich text object holds at most 2000 characters, any rich text array at most
# 100 elements, and the whole request at most 500KB. There is no separate comment
# limit, so the real ceiling on one comment is 100 x 2000 characters. Nothing that
# belongs on a board card is anywhere near that, and a request over either cap is
# rejected whole with a 400 - losing the entire comment rather than its tail - so
# the text is cut to NOTION_COMMENT_MAX_CHARS first and chunked at 1900 after.
# At the 8000 default that is five objects; the clamp below keeps it under the
# 100-object cap even if board.env sets something silly.
#
# Cutting happens inside jq, which counts Unicode codepoints the way Notion's
# limit does, so a multi-byte character is never split in half. A comment that
# has to be cut is archived whole first, by board_archive_comment above, and the
# note on the end of the cut text names that file - so the one comment that says
# there is more to read is also the one that says where it is.
NOTION_COMMENT_HARD_MAX=180000   # 95 chunks of 1900, still inside the array cap

notion_comment() {
  local hook="$1" page="$2" text="$3"
  local body="$NOTION_TMP/comment.json" code len max out over note archive

  # Never post an empty comment. A caller with nothing to say says nothing.
  if [ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ]; then
    board_log "$hook" "no comment text for $page; nothing posted"
    return 0
  fi

  max="${NOTION_COMMENT_MAX_CHARS:-8000}"
  case "$max" in
    ''|*[!0-9]*|0) board_log "$hook" "NOTION_COMMENT_MAX_CHARS is not a positive integer; using 8000"; max=8000 ;;
  esac
  if [ "$max" -gt "$NOTION_COMMENT_HARD_MAX" ]; then
    board_log "$hook" "NOTION_COMMENT_MAX_CHARS is $max, above what Notion's 100-object array cap allows; using $NOTION_COMMENT_HARD_MAX"
    max="$NOTION_COMMENT_HARD_MAX"
  fi

  len="$(printf '%s' "$text" | jq -Rs 'length' 2>/dev/null || printf '')"
  case "$len" in ''|*[!0-9]*) len=0 ;; esac

  # Nothing is posted when the board is off, so there is nothing for an archive
  # to be the rest of. Archiving here would file a run nobody was ever told about.
  if board_disabled; then
    board_log "$hook" "board writes disabled; would comment on $page"
    return 0
  fi

  # $out is the text that actually gets posted. Under the cap that is the text
  # itself, untouched. Over it, the whole text is archived first and the note
  # names the archive, because a note pointing at nothing is worse than no note.
  out="$text"
  if [ "$len" -gt "$max" ]; then
    over=$((len - max))
    if archive="$(board_archive_comment "$hook" "$page" "$text")"; then
      note="[Cut to fit a Notion comment. The other $over characters, and this text in full, are in $archive]"
      board_log "$hook" "comment for $page is $len characters; cutting to $max (Notion allows 2000 per rich text object and 100 objects per array) and archiving the full text at $archive"
    else
      note="[Cut to fit a Notion comment. $over more characters were dropped and could not be archived; see the hook log.]"
      board_log "$hook" "comment for $page is $len characters; cutting to $max with no archive, so $over characters are lost"
    fi
    out="$(printf '%s' "$text" | jq -Rs --argjson max "$max" --arg note "$note" -r \
      '.[0:$max] + "\n\n" + $note' 2>/dev/null)"
    if [ -z "$out" ]; then
      board_log "$hook" "could not cut the comment for $page; nothing posted"
      return 1
    fi
  fi

  if [ -n "${BOARD_DRY_RUN:-}" ]; then
    board_log "$hook" "dry run: comment on $page: $(printf '%s' "$out" | head -1)"
    # The whole thing on stderr, not just its first line: a dry run that only
    # counts characters is no way to check what a cut comment ends up saying.
    printf '%s\n' "$out" >&2
    return 0
  fi

  jq -n --arg p "$page" --arg t "$out" '
    def chunks: if (. | length) <= 1900 then [.] else [.[0:1900]] + (.[1900:] | chunks) end;
    {parent: {page_id: $p}, rich_text: ($t | chunks | map({text: {content: .}}))}
  ' > "$body" 2>/dev/null || { board_log "$hook" "could not build the comment body"; return 1; }

  code="$(notion_api POST "$NOTION_API/v1/comments" "$body")"
  if [ "$code" = "200" ]; then
    board_log "$hook" "commented on $page"
    return 0
  fi
  board_log "$hook" "HTTP $code commenting on $page: $(notion_error_text)"
  return 1
}

# board_write HOOK PAGE_ID COLUMN [COMMENT]
# The one entry point the hooks use. Always returns 0: a board write must not
# decide whether a session continues.
board_write() {
  local hook="$1" page="$2" col="$3" comment="${4:-}"
  if [ -z "$page" ]; then
    board_log "$hook" "no board item resolved, nothing to move to \"$col\" (see README, Which board item)"
    return 0
  fi
  require_tools "$hook" || return 0
  notion_tmp_init "$hook" || { board_log "$hook" "could not create a temp directory"; return 0; }
  if notion_load_token "$hook"; then
    notion_set_status "$hook" "$page" "$col" || true
    if [ -n "$comment" ]; then notion_comment "$hook" "$page" "$comment" || true; fi
  fi
  NOTION_TOKEN=""
  notion_tmp_cleanup
  return 0
}

# board_comment HOOK PAGE_ID TEXT
# Say something on a row without moving it. Same envelope and same promise as
# board_write: every failure is logged and swallowed, and it always returns 0,
# because nothing about Notion decides whether a session continues. Used where a
# transition has something worth reading but no column of its own - a clean
# subagent finish, where TaskCompleted still owns the move to Done.
board_comment() {
  local hook="$1" page="$2" text="$3"
  if [ -z "$page" ]; then
    board_log "$hook" "no board item resolved, nothing to comment on (see README, Which board item)"
    return 0
  fi
  if [ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ]; then
    board_log "$hook" "no comment text; nothing posted on $page"
    return 0
  fi
  require_tools "$hook" || return 0
  notion_tmp_init "$hook" || { board_log "$hook" "could not create a temp directory"; return 0; }
  if notion_load_token "$hook"; then
    notion_comment "$hook" "$page" "$text" || true
  fi
  NOTION_TOKEN=""
  notion_tmp_cleanup
  return 0
}
