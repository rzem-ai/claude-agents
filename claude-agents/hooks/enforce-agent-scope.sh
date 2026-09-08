#!/usr/bin/env bash
# PreToolUse: per-agent tool scoping.
#
# permissions.deny is session-scoped, so it cannot say "spec-writer may only
# write under docs/specs/" while coder writes anywhere. This hook is where the
# per-agent half of that lives. It switches on agent_type and denies the tool
# calls the agent's own Invariants section forbids, quoting the invariant back
# so the agent knows which line it hit.
#
# It fails open. A bug here must not stop the fleet working. Be clear about what
# that costs: for the per-agent half there is no second lock, because that is the
# half permissions.deny cannot express. The session-wide half - credentials,
# curl, sudo, destructive git - is denied in settings and by the sandbox whatever
# this hook does, and the sandbox is the thing that actually contains an agent.
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

# The command a segment actually runs: leading VAR=value assignments dropped,
# then the basename of the first word. Empty if the segment is only assignments.
leading_token() {
  local seg="$1" tok next
  while :; do
    tok="$(printf '%s' "$seg" | awk '{print $1}')"
    case "$tok" in
      *=*) ;;
      *) break ;;
    esac
    next="$(printf '%s' "$seg" | sed -E 's/^[^[:space:]]+[[:space:]]+//')"
    if [ "$next" = "$seg" ]; then tok=""; break; fi
    seg="$next"
  done
  printf '%s\n' "${tok##*/}"
}

enforce_scout() {
  if is_write_tool "$tool_name"; then
    deny "scout invariant: \"Never edit, write or create a file, and leave the working tree exactly as you found it.\" scout answers in paths, line numbers and quoted excerpts only. Hand the change to coder."
  fi
  [ "$tool_name" = "Bash" ] || return 0
  [ -n "$command_str" ] || return 0

  local scan seg first next tok verb
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
    # Strip leading VAR=value assignments, keeping both the command token
    # and the remaining segment - the sed and git checks below inspect the
    # arguments in $first. leading_token() carries the progress check the
    # old inline loop lacked: a segment that is only an assignment
    # (FOO=bar with nothing after it) made the sed a no-op and spun until
    # the hook timeout.
    tok="$(leading_token "$seg")"
    [ -n "$tok" ] || continue
    first="$seg"
    while :; do
      case "$(printf '%s' "$first" | awk '{print $1}')" in
        *=*) ;;
        *) break ;;
      esac
      next="$(printf '%s' "$first" | sed -E 's/^[^[:space:]]+[[:space:]]+//')"
      [ "$next" = "$first" ] && { first=""; break; }
      first="$next"
    done

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

# -------------------------------------------------------------------- reviewer
# Invariants: "Never edit, write or create a file. Not a fix, not a test, not a
# note.", "Never run a git command that writes: no commit, push, force-push,
# checkout, stash, reset or rebase. Read-only git only." and "Never run tests,
# builds or installs. If something needs running, that is a finding, not a
# task."
#
# git is an allowlist because "read-only git only" is wider than the seven verbs
# the invariant names, and a denylist would miss the eighth. Everything else is
# a denylist: the reviewer reads the tree freely, it just never runs the suite.
REVIEWER_ALLOWED_GIT=" log show blame diff ls-files status shortlog describe rev-parse rev-list cat-file grep whatchanged "
REVIEWER_DENIED_CMDS=" npm pnpm yarn bun npx pnpx bunx pip pip3 pipx poetry uv gem bundle composer cargo rustc go make cmake ninja gradle mvn dotnet swift xcodebuild tsc vite webpack esbuild rollup jest vitest mocha ava karma pytest tox nox playwright cypress rspec phpunit ctest bazel docker docker-compose podman brew apt apt-get "

enforce_reviewer() {
  if is_write_tool "$tool_name"; then
    deny "reviewer invariant: \"Never edit, write or create a file. Not a fix, not a test, not a note.\" The report is the whole output: a reviewer that edits makes the diff Alex approves a different diff from the one he read. Raise it as a finding and let coder make the change."
  fi
  [ "$tool_name" = "Bash" ] || return 0
  [ -n "$command_str" ] || return 0

  local scan seg tok verb
  scan="$(strip_quoted "$command_str")"
  scan="$(printf '%s' "$scan" | sed -E 's/(\|\||&&|;|\||&)/\n/g')"
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$seg" ] || continue
    tok="$(leading_token "$seg")"
    [ -n "$tok" ] || continue

    case "$tok" in
      git)
        verb="$(printf '%s' "$seg" | awk '{print $2}')"
        case "$REVIEWER_ALLOWED_GIT" in
          *" $verb "*) ;;
          *) deny "reviewer invariant: \"Never run a git command that writes: no commit, push, force-push, checkout, stash, reset or rebase. Read-only git only.\" \"git $verb\" is not a read-only verb. Read the history with git log, show, blame, diff or ls-files; anything that changes a ref belongs to coder." ;;
        esac
        ;;
    esac

    case "$REVIEWER_DENIED_CMDS" in
      *" $tok "*)
        deny "reviewer invariant: \"Never run tests, builds or installs. If something needs running, that is a finding, not a task.\" \"$tok\" is one of those. Say in a finding what needs running and what you expect it to show, and let coder run it." ;;
    esac
  done <<< "$scan"
  return 0
}

# ----------------------------------------------------------------- ui-designer
# Invariant: "Never run a git command that writes, and never install anything
# into the product repo."
#
# Bash stays open otherwise, because "use Bash only to build, serve or
# screenshot a prototype" is the job. So the package managers are matched on
# their install verbs rather than denied outright: `npx serve` and a prototype
# build are allowed, `npm install` is not.
UI_DESIGNER_ALLOWED_GIT=" log show blame diff ls-files status shortlog describe rev-parse rev-list cat-file grep whatchanged "
UI_DESIGNER_INSTALLERS=" npm pnpm yarn bun pip pip3 pipx poetry uv gem bundle composer cargo go brew apt apt-get "
UI_DESIGNER_INSTALL_VERBS=" install i ci add require get remove uninstall update upgrade link "

enforce_ui_designer() {
  [ "$tool_name" = "Bash" ] || return 0
  [ -n "$command_str" ] || return 0

  local scan seg tok verb
  scan="$(strip_quoted "$command_str")"
  scan="$(printf '%s' "$scan" | sed -E 's/(\|\||&&|;|\||&)/\n/g')"
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$seg" ] || continue
    tok="$(leading_token "$seg")"
    [ -n "$tok" ] || continue
    verb="$(printf '%s' "$seg" | awk '{print $2}')"

    case "$tok" in
      git)
        case "$UI_DESIGNER_ALLOWED_GIT" in
          *" $verb "*) ;;
          *) deny "ui-designer invariant: \"Never run a git command that writes, and never install anything into the product repo.\" \"git $verb\" is not a read-only verb. Your prototypes are the deliverable; a coder builds and commits the real thing." ;;
        esac
        ;;
    esac

    case "$UI_DESIGNER_INSTALLERS" in
      *" $tok "*)
        case "$UI_DESIGNER_INSTALL_VERBS" in
          *" $verb "*)
            deny "ui-designer invariant: \"Never run a git command that writes, and never install anything into the product repo.\" \"$tok $verb\" installs into the repo. A prototype is self-contained: build it from what is already there, and name any dependency the real thing would need in the handoff." ;;
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
  reviewer)      enforce_reviewer ;;
  ui-designer)   enforce_ui_designer ;;
  *)             ;;
esac

allow
