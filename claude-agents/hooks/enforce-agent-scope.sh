#!/usr/bin/env bash
# PreToolUse: per-agent tool scoping.
#
# permissions.deny is session-scoped, so it cannot say "spec-writer may only
# write under docs/specs/" while coder writes anywhere. This hook is where the
# per-agent half of that lives. It switches on agent_type and denies the tool
# calls the agent's own Invariants section forbids, quoting the invariant back
# so the agent knows which line it hit.
#
# It fails open. A bug here must not stop the fleet working, and this is a
# second lock on invariants that are also stated in the agent bodies and backed
# by host-level permissions.deny - not the only thing standing between an agent
# and the filesystem.
set -euo pipefail

HOOK=PreToolUse

trap 'printf "%s [PreToolUse] unexpected error on line %s; allowing the call\n" "$(date -u "+%Y-%m-%dT%H:%M:%SZ")" "$LINENO" >&2; exit 0' ERR

log() { printf '%s [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$HOOK" "$*" >&2; }

allow() { exit 0; }

deny() {
  # $1 the reason shown to the agent.
  trap - ERR
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  log "denied: $1"
  exit 0
}

# Absolute, lexically normalised. No realpath: the target of a Write may not
# exist yet, and macOS has no realpath in the base system.
lex_abs() {
  local p="$1" cwd="$2" out="" seg oldifs
  case "$p" in
    /*) ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
    *) p="${cwd:-/}/$p" ;;
  esac
  oldifs="$IFS"; IFS='/'; set -f; set -- $p; set +f; IFS="$oldifs"
  for seg in "$@"; do
    case "$seg" in
      ''|'.') ;;
      '..') out="${out%/*}" ;;
      *) out="$out/$seg" ;;
    esac
  done
  printf '%s\n' "${out:-/}"
}

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  log "jq is not installed, so per-agent scoping cannot run. Every call is allowed. Install jq (macOS: brew install jq)."
  allow
fi

if ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
  log "hook input is not valid JSON; allowing the call"
  allow
fi

agent_type="$(printf '%s' "$input" | jq -r '.agent_type // ""')"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // ""')"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""')"
command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"

# A plugin agent can arrive as "scout" or as "plugin-name:scout".
agent="${agent_type##*:}"

# No agent_type means the main session, which these rules do not govern.
if [ -z "$agent" ]; then allow; fi

is_write_tool() {
  case "$1" in
    Write|Edit|MultiEdit|NotebookEdit) return 0 ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------------ spec-writer
# Invariant: "Never write anywhere except under `docs/specs/`: not source, not
# config, not tests, and never a plan under `docs/plans/`."
enforce_spec_writer() {
  is_write_tool "$tool_name" || return 0
  if [ -z "$file_path" ]; then
    log "spec-writer called $tool_name with no path in tool_input; allowing"
    return 0
  fi
  local abs; abs="$(lex_abs "$file_path" "$cwd")"
  case "$abs" in
    */docs/specs/*) return 0 ;;
  esac
  deny "spec-writer invariant: \"Never write anywhere except under docs/specs/: not source, not config, not tests, and never a plan under docs/plans/.\" $tool_name targeted $abs. Write the spec to docs/specs/<issue>.md instead. Anything else belongs to the lead."
}

# ----------------------------------------------------------------------- scout
# Invariants: "Never edit, write or create a file", and a Bash allowlist -
# "run only commands that read - ls, cat, head, tail, sed -n, wc, file, rg,
# grep, find, and read-only git log, git show, git blame, git diff,
# git ls-files."
#
# cd, pwd, echo and true are allowed on top of that list because none of them
# can change state and every one of them appears inside an otherwise legal
# command. That is the only addition; see hooks/README.md.
SCOUT_ALLOWED_CMDS=" ls cat head tail sed wc file rg grep find git cd pwd echo true "
SCOUT_ALLOWED_GIT=" log show blame diff ls-files "

# Removes single- and double-quoted spans so a redirection character inside a
# search pattern (grep -R '=>' src) is not mistaken for a redirection.
strip_quoted() {
  printf '%s' "$1" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g'
}

enforce_scout() {
  if is_write_tool "$tool_name"; then
    deny "scout invariant: \"Never edit, write or create a file, and leave the working tree exactly as you found it.\" scout answers in paths, line numbers and quoted excerpts only. Hand the change to coder."
  fi
  [ "$tool_name" = "Bash" ] || return 0
  [ -n "$command_str" ] || return 0

  local scan seg first tok verb
  scan="$(strip_quoted "$command_str")"
  # Discarding output is not a state change, so let 2>/dev/null through before
  # looking for redirections.
  scan="$(printf '%s' "$scan" | sed -E 's/[0-9]?>>?[[:space:]]*\/dev\/null//g')"

  case "$scan" in
    *'$('*|*'`'*)
      deny "scout invariant: no command substitution. The command contains \$( or a backtick, which can hide a write behind a read. Run the inner command on its own." ;;
    *'>'*)
      deny "scout invariant: \"no redirection into a file\". scout leaves the working tree exactly as it found it, so > and >> are not available. Read the file and quote it instead." ;;
    *'<('*|*'>('*)
      deny "scout invariant: no process substitution. Run the commands separately." ;;
  esac

  # Split on the shell operators that start a new command.
  scan="$(printf '%s' "$scan" | sed -E 's/(\|\||&&|;|\||&)/\n/g')"
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$seg" ] || continue
    # Skip leading VAR=value assignments.
    first="$seg"
    while :; do
      tok="$(printf '%s' "$first" | awk '{print $1}')"
      case "$tok" in
        *=*) first="$(printf '%s' "$first" | sed -E 's/^[^[:space:]]+[[:space:]]+//')" ;;
        *) break ;;
      esac
      [ -n "$first" ] || break
    done
    tok="$(printf '%s' "$first" | awk '{print $1}')"
    tok="${tok##*/}"
    [ -n "$tok" ] || continue

    case "$SCOUT_ALLOWED_CMDS" in
      *" $tok "*) ;;
      *) deny "scout invariant: \"run only commands that read - ls, cat, head, tail, sed -n, wc, file, rg, grep, find, and read-only git log, git show, git blame, git diff, git ls-files.\" \"$tok\" is not on that list. If the answer needs a state change, hand it to an agent that is allowed to make one." ;;
    esac

    case "$tok" in
      sed)
        case " $first " in
          *" -i"*|*" --in-place"*)
            deny "scout invariant: sed -i edits the file in place. scout leaves the working tree exactly as it found it." ;;
        esac
        case " $first " in
          *" -n"*) ;;
          *) deny "scout invariant: the allowlist is \"sed -n\", not sed. Add -n and an explicit p, so sed only prints." ;;
        esac
        ;;
      find)
        case " $first " in
          *" -exec"*|*" -execdir"*|*" -ok"*|*" -okdir"*|*" -delete"*|*" -fprintf"*|*" -fls"*|*" -fprint"*)
            deny "scout invariant: find -exec, -delete and the -f* actions run or write things. Use find to locate files and read them separately." ;;
        esac
        ;;
      git)
        verb="$(printf '%s' "$first" | awk '{print $2}')"
        case "$SCOUT_ALLOWED_GIT" in
          *" $verb "*) ;;
          *) deny "scout invariant: read-only git only - log, show, blame, diff, ls-files. \"git $verb\" is not one of them." ;;
        esac
        ;;
    esac
  done <<< "$scan"
  return 0
}

# ---------------------------------------------------------------- fleet-steward
# Invariants: "Never touch anything outside the `claude-agents` working copy"
# and "Never run a git command that rewrites shared history: no force-push, no
# reset, no rebase onto a shared branch", plus "Never merge."
steward_repo_root() {
  if [ -n "${CLAUDE_AGENTS_REPO:-}" ]; then
    printf '%s\n' "${CLAUDE_AGENTS_REPO%/}"
    return 0
  fi
  # Installed from the marketplace source, the plugin sits at
  # <repo>/claude-agents, next to <repo>/.claude-plugin/marketplace.json.
  local hook_dir plugin_root parent
  hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  plugin_root="$(dirname "$hook_dir")"
  parent="$(dirname "$plugin_root")"
  if [ "$(basename "$plugin_root")" = "claude-agents" ] && [ -f "$parent/.claude-plugin/marketplace.json" ]; then
    printf '%s\n' "$parent"
    return 0
  fi
  return 1
}

enforce_fleet_steward() {
  if is_write_tool "$tool_name"; then
    if [ -z "$file_path" ]; then
      log "fleet-steward called $tool_name with no path in tool_input; allowing"
      return 0
    fi
    local abs root; abs="$(lex_abs "$file_path" "$cwd")"
    if root="$(steward_repo_root)"; then
      case "$abs" in
        "$root"/*) return 0 ;;
      esac
      deny "fleet-steward invariant: \"Never touch anything outside the claude-agents working copy.\" $tool_name targeted $abs, which is outside $root. The steward files and proposes; it does not edit other repositories."
    else
      # No repo root could be resolved, so fall back to the weaker check and say
      # so, rather than pretending this is airtight.
      case "$abs" in
        */claude-agents/*) return 0 ;;
      esac
      deny "fleet-steward invariant: \"Never touch anything outside the claude-agents working copy.\" $tool_name targeted $abs, which is not under a claude-agents directory. Set CLAUDE_AGENTS_REPO in ~/.config/claude-agents/board.env if the working copy lives somewhere this check cannot see."
    fi
  fi

  [ "$tool_name" = "Bash" ] || return 0
  [ -n "$command_str" ] || return 0

  local scan seg verb
  scan="$(strip_quoted "$command_str")"
  scan="$(printf '%s' "$scan" | sed -E 's/(\|\||&&|;|\||&)/\n/g')"
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    case "$(printf '%s' "$seg" | awk '{print $1}')" in
      git|*/git) ;;
      *) continue ;;
    esac
    verb="$(printf '%s' "$seg" | awk '{print $2}')"
    case "$verb" in
      merge|rebase|reset|filter-branch|filter-repo)
        deny "fleet-steward invariant: \"Never merge\" and \"never run a git command that rewrites shared history: no force-push, no reset, no rebase onto a shared branch.\" \"git $verb\" is one of those. File it and propose it; Alex decides on the pull request." ;;
      push)
        case " $seg " in
          *" --force"*|*" -f "*|*" --force-with-lease"*|*" --delete "*|*" --mirror"*)
            deny "fleet-steward invariant: no force-push and no history rewrite. Push the branch normally and open a pull request." ;;
        esac
        case " $seg " in
          *" main"*|*" master"*|*" refs/heads/main"*|*" refs/heads/master"*)
            deny "fleet-steward invariant: \"no push to a default branch\". Push the migration branch and open a pull request instead." ;;
        esac
        ;;
    esac
  done <<< "$scan"
  return 0
}

case "$agent" in
  spec-writer)   enforce_spec_writer ;;
  scout)         enforce_scout ;;
  fleet-steward) enforce_fleet_steward ;;
  *)             ;;
esac

allow
