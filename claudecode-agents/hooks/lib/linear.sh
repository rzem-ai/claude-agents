# shellcheck shell=bash
# Shared helpers for the board hooks, Linear edition. Sourced, never executed.
#
# Everything here is written for bash 3.2, because that is what /bin/bash is on
# macOS: no associative arrays, no ${var,,}, no mapfile, no globstar.
#
# The board lives in Linear and the API is GraphQL: one endpoint, POST only,
# and errors arrive as an `errors` array in a 200 response as often as they
# arrive as an HTTP status - so every call checks the body, never the code
# alone. A status move is two calls (resolve the issue and its team's states,
# then issueUpdate with a state UUID) where Notion's was one name-based PATCH;
# in exchange the auth story is one personal API key with no
# share-the-database-with-the-integration step.
#
# The token never reaches a command line. curl is driven from a --config file
# written under a 0700 temp directory, so the Authorization header never
# appears in `ps` output and never lands in a log.

# Tracing would print the token. Refuse to run traced, and turn it off anyway.
set +x

CLAUDECODE_AGENTS_CONFIG_DIR="${CLAUDECODE_AGENTS_CONFIG_DIR:-$HOME/.config/claudecode-agents}"
CLAUDECODE_AGENTS_TOKEN_FILE="${CLAUDECODE_AGENTS_TOKEN_FILE:-$CLAUDECODE_AGENTS_CONFIG_DIR/linear.token}"
CLAUDECODE_AGENTS_STATE_DIR="${CLAUDECODE_AGENTS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claudecode-agents}"

# Defaults for everything the plan did not name. board.env overrides them.
LINEAR_API="${LINEAR_API:-https://api.linear.app/graphql}"
BOARD_COL_TODO="${BOARD_COL_TODO:-To do}"
BOARD_COL_DOING="${BOARD_COL_DOING:-Doing}"
BOARD_COL_BLOCKED="${BOARD_COL_BLOCKED:-Blocked}"
BOARD_COL_BLOCKED_HUMAN="${BOARD_COL_BLOCKED_HUMAN:-Blocked by human}"
BOARD_COL_DONE="${BOARD_COL_DONE:-Done}"

# How much of a comment reaches the card. Linear takes one markdown body per
# comment rather than Notion's chunked rich-text array, but the reason for a
# cap is unchanged: a card comment is a summary, and the whole text of a long
# run belongs in the archive a cut comment points at.
BOARD_COMMENT_MAX_CHARS="${BOARD_COMMENT_MAX_CHARS:-8000}"

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
if [ -f "$CLAUDECODE_AGENTS_CONFIG_DIR/board.env" ]; then
  # shellcheck disable=SC1091
  . "$CLAUDECODE_AGENTS_CONFIG_DIR/board.env"
fi

BOARD_LOG_FILE="${BOARD_LOG_FILE:-$CLAUDECODE_AGENTS_STATE_DIR/log/hooks.log}"

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
# that is only about Linear.
board_soft_fail() {
  board_log "$1" "board write skipped: $2"
  return 1
}

board_disabled() {
  if [ "${CLAUDECODE_AGENTS_BOARD:-on}" = "off" ]; then return 0; fi
  if [ -f "$CLAUDECODE_AGENTS_STATE_DIR/disabled" ]; then return 0; fi
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
  printf '%s/sessions/%s' "$CLAUDECODE_AGENTS_STATE_DIR" "$sid"
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
# message telling the human there was more to read pointed at nothing, on exactly the
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
  printf '%s/archives/%s' "$CLAUDECODE_AGENTS_STATE_DIR" "$sid"
}

# board_archive_comment HOOK ITEM_REF TEXT
# Writes the full comment text with a header saying which run it came from, and
# echoes the path it wrote. Returns 1, having logged why, if anything failed:
# an archive that could not be written is not a reason to lose the card comment
# as well, so the caller carries on and posts the cut text.
board_archive_comment() {
  local hook="$1" page="$2" text="$3"
  local dir file stamp name url n old_umask

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

  # An identifier like RZE-123 has a stable web address; a UUID's address needs
  # the workspace slug this machine does not know, so it gets no URL line.
  url=""
  case "$page" in
    [A-Za-z]*-[0-9]*) url="https://linear.app/issue/$page" ;;
  esac

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
    printf 'The comment on the card was cut to fit the board. This is the whole of it.\n\n'
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

# ------------------------------------------------------------- item ref parsing

# Accepts a Linear issue reference in any of the forms a human has in hand -
# an identifier (RZE-123), an issue URL pasted straight out of Linear, or a
# UUID, dashed or not - and returns the canonical form: the identifier
# uppercased, or the dashed lowercase UUID. The UUID test runs first so a
# UUID's own hyphens are never mistaken for a team-key identifier.
normalise_page_id() {
  local raw hex len ident
  raw="$(printf '%s' "$1" | tr -d '\r' | sed -e 's/[?#].*$//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//')"
  [ -n "$raw" ] || return 1

  if printf '%s' "$raw" | grep -Eq '^[0-9a-fA-F-]+$'; then
    hex="$(printf '%s' "$raw" | tr -cd '0-9a-fA-F')"
    len=${#hex}
    [ "$len" -eq 32 ] || return 1
    hex="$(printf '%s' "$hex" | tr 'A-F' 'a-f')"
    printf '%s-%s-%s-%s-%s\n' \
      "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}"
    return 0
  fi

  case "$raw" in
    *linear.app*/issue/*)
      # The identifier is the path segment after /issue/; anything after it is
      # a title slug, which can itself look identifier-shaped, so only that
      # segment is read.
      ident="$(printf '%s' "$raw" | sed -En 's|.*/issue/([A-Za-z][A-Za-z0-9]*-[0-9]+)([/?#].*)?$|\1|p' | head -1)"
      ;;
    *)
      ident="$(printf '%s' "$raw" | grep -Eio '^[A-Za-z][A-Za-z0-9]*-[0-9]+$' || true)"
      ;;
  esac
  [ -n "$ident" ] || return 1
  printf '%s\n' "$ident" | tr 'a-z' 'A-Z'
}

# The spawn-prompt convention. One line anywhere in the instructions:
#   Board-Item: RZE-123
# or the issue URL, or a UUID. Leading "- " and any case are tolerated;
# nothing else is.
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
#   Wire up refresh rotation [board:RZE-123]
page_id_from_task_title() {
  local text="$1" id
  id="$(printf '%s' "$text" | grep -Eio '\[board:[^]]+\]' | head -1 || true)"
  [ -n "$id" ] || return 1
  id="$(printf '%s' "$id" | sed -E 's/^\[[Bb][Oo][Aa][Rr][Dd]:[[:space:]]*//; s/[[:space:]]*\]$//')"
  normalise_page_id "$id"
}

# ------------------------------------------------------------------ Linear API

linear_tmp_init() {
  # $1 hook name. Sets LINEAR_TMP and arranges its removal.
  local hook="$1"
  umask 077
  LINEAR_TMP="$(mktemp -d "${TMPDIR:-/tmp}/claudecode-agents-$hook.XXXXXX" 2>/dev/null)" || return 1
  chmod 700 "$LINEAR_TMP" 2>/dev/null || true
  return 0
}

linear_tmp_cleanup() {
  if [ -n "${LINEAR_TMP:-}" ] && [ -d "$LINEAR_TMP" ]; then rm -rf "$LINEAR_TMP"; fi
  return 0
}

# Reads the token into LINEAR_TOKEN. Never printed, never exported, never
# passed to op. The file is rendered once by scripts/install-home.sh.
linear_load_token() {
  local hook="$1"
  if [ ! -f "$CLAUDECODE_AGENTS_TOKEN_FILE" ]; then
    board_log "$hook" "no token at $CLAUDECODE_AGENTS_TOKEN_FILE - run scripts/install-home.sh. Board not updated."
    return 1
  fi
  if [ ! -r "$CLAUDECODE_AGENTS_TOKEN_FILE" ]; then
    board_log "$hook" "token file exists but is not readable by this user. Board not updated."
    return 1
  fi
  # GNU stat and BSD stat disagree on both the flag and its meaning: -f is
  # "format" on GNU but "filesystem" on BSD, so GNU is tried first and the
  # answer is sanity-checked before it is believed.
  local mode
  mode="$(stat -c '%a' "$CLAUDECODE_AGENTS_TOKEN_FILE" 2>/dev/null || true)"
  case "$mode" in
    [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) : ;;
    *) mode="$(stat -f '%Lp' "$CLAUDECODE_AGENTS_TOKEN_FILE" 2>/dev/null || true)" ;;
  esac
  case "$mode" in
    600|400|0600|0400) : ;;
    [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7])
      board_log "$hook" "token file mode is $mode, expected 600. Fix with chmod 600 on that file." ;;
    *) board_log "$hook" "could not read the token file mode; continuing" ;;
  esac
  LINEAR_TOKEN="$(tr -d '\r\n' < "$CLAUDECODE_AGENTS_TOKEN_FILE")"
  if [ -z "$LINEAR_TOKEN" ]; then
    board_log "$hook" "token file is empty. Board not updated."
    return 1
  fi
  return 0
}

# linear_api QUERY VARIABLES_JSON
# Posts one GraphQL request. Echoes the HTTP status; the response body lands in
# $LINEAR_TMP/response.json. A personal API key is sent bare and anything else
# as a Bearer token, which is the split Linear's own docs draw between api keys
# and OAuth tokens.
linear_api() {
  local query="$1" vars="${2:-{\}}"
  local cfg="$LINEAR_TMP/curl.cfg"
  local resp="$LINEAR_TMP/response.json"
  local body="$LINEAR_TMP/request.json"
  local auth code
  case "$LINEAR_TOKEN" in
    lin_api_*) auth="$LINEAR_TOKEN" ;;
    *)         auth="Bearer $LINEAR_TOKEN" ;;
  esac
  jq -n --arg q "$query" --argjson v "$vars" '{query: $q, variables: $v}' > "$body" 2>/dev/null \
    || { printf '000\n'; return 0; }
  : > "$cfg"; chmod 600 "$cfg"
  {
    printf 'url = "%s"\n' "$LINEAR_API"
    printf 'request = "POST"\n'
    printf 'header = "Authorization: %s"\n' "$auth"
    printf 'header = "Content-Type: application/json"\n'
    printf 'silent\n'
    printf 'show-error\n'
    printf 'connect-timeout = 5\n'
    printf 'max-time = 12\n'
    printf 'retry = 1\n'
    printf 'output = "%s"\n' "$resp"
    printf 'write-out = "%%{http_code}"\n'
    printf 'data = "@%s"\n' "$body"
  } > "$cfg"
  code="$(curl --config "$cfg" 2>"$LINEAR_TMP/curl.err")" || code=""
  rm -f "$cfg"
  [ -n "$code" ] || code="000"
  printf '%s\n' "$code"
}

# GraphQL delivers most failures as an errors array in a 200, so success is
# "HTTP 200 and no errors key", checked here in one place.
linear_ok() {
  # $1 http code
  [ "$1" = "200" ] || return 1
  jq -e '.errors | length > 0' "$LINEAR_TMP/response.json" >/dev/null 2>&1 && return 1
  return 0
}

# The API error message, with anything token-shaped removed. Linear never
# echoes the token back, but a proxy in the middle might.
linear_error_text() {
  local resp="$LINEAR_TMP/response.json"
  local msg=""
  if [ -s "$resp" ]; then
    msg="$(jq -r '(.errors[0].message // .error // empty)' "$resp" 2>/dev/null || true)"
  fi
  if [ -z "$msg" ] && [ -s "$LINEAR_TMP/curl.err" ]; then
    msg="$(head -c 300 "$LINEAR_TMP/curl.err")"
  fi
  printf '%s' "${msg:-no detail}" | sed -E 's/lin_(api|oauth)_[A-Za-z0-9]+/[redacted]/g'
}

# linear_resolve HOOK ITEM_REF
# One lookup that everything else reuses: sets LINEAR_ISSUE_ID (the UUID
# mutations need) and leaves the team's workflow states in
# $LINEAR_TMP/states.json for linear_state_id to read. The ref may be an
# identifier or a UUID; the issue query takes either.
linear_resolve() {
  local hook="$1" ref="$2" code
  LINEAR_ISSUE_ID=""
  code="$(linear_api \
    'query($id: String!) { issue(id: $id) { id identifier team { states { nodes { id name } } } } }' \
    "$(jq -n --arg id "$ref" '{id: $id}')")"
  if ! linear_ok "$code"; then
    board_log "$hook" "HTTP $code resolving $ref: $(linear_error_text)"
    return 1
  fi
  LINEAR_ISSUE_ID="$(jq -r '.data.issue.id // empty' "$LINEAR_TMP/response.json" 2>/dev/null || true)"
  if [ -z "$LINEAR_ISSUE_ID" ]; then
    board_log "$hook" "no issue found for $ref: $(linear_error_text)"
    return 1
  fi
  jq '.data.issue.team.states.nodes // []' "$LINEAR_TMP/response.json" > "$LINEAR_TMP/states.json" 2>/dev/null || true
  return 0
}

# linear_state_id HOOK COLUMN
# The state UUID for a column name, from the states linear_resolve fetched.
# Matching ignores case and spaces so the default "To do" finds a team's
# "Todo" without a board.env override; anything further apart than that - a
# team that says "In Progress" where the fleet says "Doing" - is a rename in
# Linear or a BOARD_COL_* override, and kickoff's board step says which.
linear_state_id() {
  local hook="$1" col="$2" want id
  want="$(printf '%s' "$col" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
  id="$(jq -r --arg w "$want" \
    '[.[] | select((.name | ascii_downcase | gsub("[[:space:]]"; "")) == $w)][0].id // empty' \
    "$LINEAR_TMP/states.json" 2>/dev/null || true)"
  if [ -z "$id" ]; then
    board_log "$hook" "the team has no workflow state matching \"$col\". Add one in Linear, or point BOARD_COL_* in board.env at the name the team uses."
    return 1
  fi
  printf '%s\n' "$id"
}

# linear_set_status HOOK ITEM_REF COLUMN
# Requires linear_resolve to have run for ITEM_REF.
linear_set_status() {
  local hook="$1" page="$2" col="$3" state code

  if board_disabled; then
    board_log "$hook" "board writes disabled; would move $page to \"$col\""
    return 0
  fi
  if [ -n "${BOARD_DRY_RUN:-}" ]; then
    board_log "$hook" "dry run: move $page to \"$col\""
    return 0
  fi

  state="$(linear_state_id "$hook" "$col")" || return 1
  code="$(linear_api \
    'mutation($id: String!, $state: String!) { issueUpdate(id: $id, input: { stateId: $state }) { success } }' \
    "$(jq -n --arg id "$LINEAR_ISSUE_ID" --arg state "$state" '{id: $id, state: $state}')")"
  if linear_ok "$code" && jq -e '.data.issueUpdate.success == true' "$LINEAR_TMP/response.json" >/dev/null 2>&1; then
    board_log "$hook" "moved $page to \"$col\""
    return 0
  fi
  board_log "$hook" "HTTP $code moving $page to \"$col\": $(linear_error_text)"
  return 1
}

# linear_comment HOOK ITEM_REF TEXT
# Requires linear_resolve to have run for ITEM_REF, except under
# board_disabled or BOARD_DRY_RUN, where nothing is sent anywhere.
#
# One markdown body per comment, no chunking. The cap exists for the reader,
# not the API: a card comment is a summary, and a comment that has to be cut
# is archived whole first, by board_archive_comment above, so the note on the
# end of the cut text names the file with the rest. Cutting happens inside jq,
# which counts Unicode codepoints, so a multi-byte character is never split.
BOARD_COMMENT_HARD_MAX=180000

linear_comment() {
  local hook="$1" page="$2" text="$3"
  local code len max out over note archive

  # Never post an empty comment. A caller with nothing to say says nothing.
  if [ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ]; then
    board_log "$hook" "no comment text for $page; nothing posted"
    return 0
  fi

  max="${BOARD_COMMENT_MAX_CHARS:-8000}"
  case "$max" in
    ''|*[!0-9]*|0) board_log "$hook" "BOARD_COMMENT_MAX_CHARS is not a positive integer; using 8000"; max=8000 ;;
  esac
  if [ "$max" -gt "$BOARD_COMMENT_HARD_MAX" ]; then
    board_log "$hook" "BOARD_COMMENT_MAX_CHARS is $max, above the hard ceiling; using $BOARD_COMMENT_HARD_MAX"
    max="$BOARD_COMMENT_HARD_MAX"
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
      note="[Cut to fit a board comment. The other $over characters, and this text in full, are in $archive]"
      board_log "$hook" "comment for $page is $len characters; cutting to $max and archiving the full text at $archive"
    else
      note="[Cut to fit a board comment. $over more characters were dropped and could not be archived; see the hook log.]"
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

  code="$(linear_api \
    'mutation($id: String!, $body: String!) { commentCreate(input: { issueId: $id, body: $body }) { success } }' \
    "$(jq -n --arg id "$LINEAR_ISSUE_ID" --arg body "$out" '{id: $id, body: $body}')")"
  if linear_ok "$code" && jq -e '.data.commentCreate.success == true' "$LINEAR_TMP/response.json" >/dev/null 2>&1; then
    board_log "$hook" "commented on $page"
    return 0
  fi
  board_log "$hook" "HTTP $code commenting on $page: $(linear_error_text)"
  return 1
}

# Whether the API is about to be touched at all. Disabled and dry runs never
# resolve, so they need no token and no network - which is also what keeps the
# eval suites offline.
board_would_send() {
  board_disabled && return 1
  [ -n "${BOARD_DRY_RUN:-}" ] && return 1
  return 0
}

# board_write HOOK ITEM_REF COLUMN [COMMENT]
# The one entry point the hooks use. Always returns 0: a board write must not
# decide whether a session continues.
board_write() {
  local hook="$1" page="$2" col="$3" comment="${4:-}"
  if [ -z "$page" ]; then
    board_log "$hook" "no board item resolved, nothing to move to \"$col\" (see README, Which board item)"
    return 0
  fi
  require_tools "$hook" || return 0
  linear_tmp_init "$hook" || { board_log "$hook" "could not create a temp directory"; return 0; }
  if linear_load_token "$hook"; then
    if board_would_send; then
      if linear_resolve "$hook" "$page"; then
        linear_set_status "$hook" "$page" "$col" || true
        if [ -n "$comment" ]; then linear_comment "$hook" "$page" "$comment" || true; fi
      fi
    else
      linear_set_status "$hook" "$page" "$col" || true
      if [ -n "$comment" ]; then linear_comment "$hook" "$page" "$comment" || true; fi
    fi
  fi
  LINEAR_TOKEN=""
  linear_tmp_cleanup
  return 0
}

# board_comment HOOK ITEM_REF TEXT
# Say something on a row without moving it. Same envelope and same promise as
# board_write: every failure is logged and swallowed, and it always returns 0,
# because nothing about the board decides whether a session continues. Used
# where a transition has something worth reading but no column of its own - a
# clean subagent finish, where TaskCompleted still owns the move to Done.
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
  linear_tmp_init "$hook" || { board_log "$hook" "could not create a temp directory"; return 0; }
  if linear_load_token "$hook"; then
    if board_would_send; then
      if linear_resolve "$hook" "$page"; then
        linear_comment "$hook" "$page" "$text" || true
      fi
    else
      linear_comment "$hook" "$page" "$text" || true
    fi
  fi
  LINEAR_TOKEN=""
  linear_tmp_cleanup
  return 0
}
