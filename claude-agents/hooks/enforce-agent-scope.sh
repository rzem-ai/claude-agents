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

# The subcommand a segment would actually run: the first word after the command
# word that is not an option, and not an option's value.
#
# Two roles need it and neither is only about git - fleet-steward asks which git
# verb, ui-designer asks that AND which package-manager verb, since its
# invariant bans installing rather than bans npm. So the command word is dropped
# BY POSITION, because the shell's first word is the command whatever it is
# called.
#
# Three ways this has been got wrong, all of them live at some point:
#
#   awk '{print $2}'      read "-C" as the verb of `git -C /path log`. Against
#                         an allowlist that denies (scout, reviewer,
#                         ui-designer); against fleet-steward's denylist it
#                         ALLOWS, so `git -C /path push --force` walked past a
#                         ban. Fixed, item 17.
#   "${1#*git}"           strips to the first literal "git" in the string, so
#                         `/opt/git/bin/git merge` had a verb of "/bin/git", and
#                         `npm install react` - which contains no "git" at all -
#                         had a verb of "npm", silently retiring ui-designer's
#                         entire install ban.
#   collapsing every \.   fixed escapes in the path and broke them in the verb:
#                         `git \merge` runs merge, and read as "xerge".
#
# What it is not: a shell. `command git merge`, `env git merge` and
# `x=m; git ${x}erge` all defeat it, because a denylist over unexpanded text
# always loses to expansion. See the note in this file's header - the scope hook
# is a role reminder, not a containment boundary.
sub_verb() {
  local seg="$1" tok skip_next=no
  # Undo what a backslash does, in the shell's own order: a trailing one
  # continues the line and vanishes; one before whitespace joins that
  # whitespace into the word; any other quotes the next character and
  # disappears. The placeholder keeps an escaped space from splitting a path
  # into two words without pretending to know what the path says.
  seg="$(printf '%s' "$seg" | sed -e 's/\\$//' -e 's/\\\([[:space:]]\)/_/g' -e 's/\\\(.\)/\1/g')"
  # shellcheck disable=SC2086 # deliberate word splitting: this is a word scan
  set -- $seg
  [ "$#" -gt 0 ] || { printf ''; return 0; }
  shift
  for tok in "$@"; do
    if [ "$skip_next" = yes ]; then skip_next=no; continue; fi
    case "$tok" in
      # git's global options that take a SEPARATE value, checked against the
      # installed git rather than recalled. --attr-source does take one.
      # --exec-path does NOT - it prints the path and exits - so listing it
      # here made it swallow the verb that followed. --super-prefix was
      # removed in git 2.49 and is gone from this list with it.
      -C|-c|--git-dir|--work-tree|--namespace|--attr-source|--config-env)
        skip_next=yes; continue ;;
      -*) continue ;;
      *) printf '%s' "$tok"; return 0 ;;
    esac
  done
  printf ''
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
#
# Use this for redirection and process substitution only. Those are inert inside
# either kind of quote, so erasing both is correct for them and nothing else.
strip_quoted() {
  printf '%s' "$1" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g'
}

# Removes single-quoted spans only, because those are the only ones that disarm
# a substitution. The shell expands $( ) and backticks inside double quotes:
#
#   echo "$(touch /tmp/proof)"   runs touch
#   echo '$(touch /tmp/proof)'   prints the text
#
# Checking the fully stripped string for "$(" therefore answered the wrong
# question, and every substitution wrapped in double quotes was waved through.
# The two checks need different strippers; they used to share one.
strip_single_quoted() {
  printf '%s' "$1" | sed -e "s/'[^']*'/''/g"
}

# sed writes files without any redirection character: `w file` and `W file`
# write, `s/x/y/w file` writes, and `e` executes a command. The script is
# almost always quoted, so the old checks never saw it - `sed -n 'w /tmp/proof'`
# looked like an ordinary `sed -n` read.
#
# Rather than parse sed, this matches a write or execute command at a position
# where sed would take one: the start of the script, or after an address, a
# semicolon or a brace. Addresses and regexes are left alone, so
# `sed -n '/warning/p'` and `sed -n '1,50p'` still pass.
# No backreference: grep here may be ugrep, which rejects them in ERE. The three
# alternatives are a w/W command after an address terminator, an `e` command,
# and a `w` flag on a substitution.
SED_WRITE_RE="(^|[[:space:];{}0-9\$/,'\"])[wW]([[:space:]]|$)|(^|[[:space:];{}'\"])e([[:space:]]|$)|s[/|#,:].*[/|#,:][[:alnum:]]*w([[:space:]]|$)"
sed_writes() {
  printf '%s' "$1" | grep -Eq "$SED_WRITE_RE"
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

  local scan subst_scan seg first next tok verb
  scan="$(strip_quoted "$command_str")"
  # Discarding output is not a state change, so let 2>/dev/null through before
  # looking for redirections.
  scan="$(printf '%s' "$scan" | sed -E 's/[0-9]?>>?[[:space:]]*\/dev\/null//g')"
  # Substitution survives double quotes, so it gets its own, weaker strip.
  subst_scan="$(strip_single_quoted "$command_str")"

  # sed can write with no redirection character at all, and its script is
  # normally quoted, so this has to look at the command as written.
  if printf '%s' "$scan" | grep -Eq '(^|[[:space:];|&])sed([[:space:]]|$)' && sed_writes "$command_str"; then
    deny "scout invariant: \"leave the working tree exactly as you found it.\" That sed script contains a w, W or e command, which writes a file or runs a program - a quoted script is still a script. Use sed -n with p to print, and hand any change to coder."
  fi

  case "$subst_scan" in
    *'$('*|*'`'*)
      deny "scout invariant: no command substitution. The command contains \$( or a backtick, which can hide a write behind a read. Note that double quotes do not disarm it - \"\$(...)\" still runs. Run the inner command on its own." ;;
  esac

  case "$scan" in
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
        verb="$(sub_verb "${first}")"
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

  local scan seg verb root target abs
  scan="$(strip_quoted "$command_str")"
  scan="$(printf '%s' "$scan" | sed -E 's/[0-9]?>>?[[:space:]]*\/dev\/null//g')"

  # The steward genuinely needs a shell - it runs the evals and prepares a
  # branch - so its Bash cannot be an allowlist of readers the way scout's is.
  # What it must not do is write outside its own working copy, and the branch
  # below only ever inspected git verbs, so every ordinary shell write sailed
  # past: `printf changed > /tmp/outside-repo.txt` was accepted in full.
  #
  # Redirection targets are therefore resolved and checked. This is a real
  # narrowing, not a complete boundary: a program the steward runs can still
  # write wherever the process can, and no shell-level check can see that. That
  # limit is stated in fleet-steward.md rather than papered over.
  if root="$(steward_repo_root)"; then :; else root=""; fi
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    target="$(printf '%s' "$target" | sed -E 's/^[0-9]*>>?[[:space:]]*//')"
    [ -n "$target" ] || continue
    case "$target" in
      '&'*) continue ;;   # 2>&1 and friends duplicate a descriptor, not a file
    esac
    abs="$(lex_abs "$target" "$cwd")"
    # The steward needs somewhere to stage a diff, so its own temporary
    # directory is allowed - but only that one. Bare /tmp is shared with every
    # other user and process on the box, which is the sort of "outside the
    # working copy" the invariant is actually about.
    case "$abs" in
      "${TMPDIR:-/nonexistent-tmpdir}"/*|/dev/*) continue ;;
    esac
    if [ -n "$root" ]; then
      case "$abs" in
        "$root"/*) continue ;;
      esac
      deny "fleet-steward invariant: \"Never touch anything outside the claude-agents working copy.\" This command redirects into $abs, which is outside $root. Write inside the working copy, or into a temporary directory."
    else
      case "$abs" in
        */claude-agents/*) continue ;;
      esac
      deny "fleet-steward invariant: \"Never touch anything outside the claude-agents working copy.\" This command redirects into $abs, which is not under a claude-agents directory. Set CLAUDE_AGENTS_REPO in ~/.config/claude-agents/board.env if the working copy lives somewhere this check cannot see."
    fi
  done <<< "$(printf '%s' "$scan" | grep -Eo '[0-9]?>>?[[:space:]]*[^[:space:];|&]+' || true)"

  case "$(strip_single_quoted "$command_str")" in
    *'$('*|*'`'*)
      # Not a blanket ban: the steward writes shell. But a substitution hides
      # its own redirections from the check above, so it has to be spelled out.
      deny "fleet-steward invariant: \"Never touch anything outside the claude-agents working copy.\" A command substitution hides where its inner command writes, so this check cannot confirm the write stays inside the working copy. Run the inner command on its own line." ;;
  esac

  scan="$(printf '%s' "$scan" | sed -E 's/(\|\||&&|;|\||&)/\n/g')"
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    case "$(printf '%s' "$seg" | awk '{print $1}')" in
      git|*/git) ;;
      *) continue ;;
    esac
    verb="$(sub_verb "${seg}")"
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
# Both lists are allowlists now. The command list used to be a denylist of build
# tools, and a denylist of things that run code can never be finished: it named
# forty package managers and test runners and still let `touch` create a file,
# because `touch` is not a build tool and nobody had thought of it. The reviewer
# needs to read a tree and its history, which is a small, closed set of commands,
# so state that set instead of trying to enumerate its complement.
#
# It is scout's list plus the read-only git verbs a review actually reaches for -
# a reviewer looks at status and rev-parse where a scout does not - and plus
# awk/sort/uniq/comm/diff/cut/tr/column, which shape output without touching it.
REVIEWER_ALLOWED_GIT=" log show blame diff ls-files status shortlog describe rev-parse rev-list cat-file grep whatchanged "
REVIEWER_ALLOWED_CMDS=" ls cat head tail sed wc file rg grep find git cd pwd echo true awk sort uniq comm diff cut tr column basename dirname stat od xxd "

enforce_reviewer() {
  if is_write_tool "$tool_name"; then
    deny "reviewer invariant: \"Never edit, write or create a file. Not a fix, not a test, not a note.\" The report is the whole output: a reviewer that edits makes the diff Alex approves a different diff from the one he read. Raise it as a finding and let coder make the change."
  fi
  [ "$tool_name" = "Bash" ] || return 0
  [ -n "$command_str" ] || return 0

  local scan subst_scan seg tok verb
  scan="$(strip_quoted "$command_str")"
  scan="$(printf '%s' "$scan" | sed -E 's/[0-9]?>>?[[:space:]]*\/dev\/null//g')"
  subst_scan="$(strip_single_quoted "$command_str")"

  if printf '%s' "$scan" | grep -Eq '(^|[[:space:];|&])sed([[:space:]]|$)' && sed_writes "$command_str"; then
    deny "reviewer invariant: \"Never edit, write or create a file. Not a fix, not a test, not a note.\" That sed script contains a w, W or e command, which writes a file or runs a program. Quote it however you like; it is still a script."
  fi

  case "$subst_scan" in
    *'$('*|*'`'*)
      deny "reviewer invariant: no command substitution. \$( and backticks can hide a write or a test run behind something that reads like an inspection, and double quotes do not disarm them. Run the inner command on its own." ;;
  esac

  case "$scan" in
    *'>'*)
      deny "reviewer invariant: \"Never edit, write or create a file. Not a fix, not a test, not a note.\" > and >> create files. The report is the whole output." ;;
    *'<('*|*'>('*)
      deny "reviewer invariant: no process substitution. Run the commands separately." ;;
  esac

  scan="$(printf '%s' "$scan" | sed -E 's/(\|\||&&|;|\||&)/\n/g')"
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$seg" ] || continue
    tok="$(leading_token "$seg")"
    [ -n "$tok" ] || continue

    case "$REVIEWER_ALLOWED_CMDS" in
      *" $tok "*) ;;
      *) deny "reviewer invariant: \"Never run tests, builds or installs. If something needs running, that is a finding, not a task.\" \"$tok\" is not one of the commands a reviewer reads with. Say in a finding what needs running and what you expect it to show, and let coder run it." ;;
    esac

    case "$tok" in
      git)
        verb="$(sub_verb "${seg}")"
        case "$REVIEWER_ALLOWED_GIT" in
          *" $verb "*) ;;
          *) deny "reviewer invariant: \"Never run a git command that writes: no commit, push, force-push, checkout, stash, reset or rebase. Read-only git only.\" \"git $verb\" is not a read-only verb. Read the history with git log, show, blame, diff or ls-files; anything that changes a ref belongs to coder." ;;
        esac
        ;;
      sed)
        case " $seg " in
          *" -i"*|*" --in-place"*)
            deny "reviewer invariant: sed -i edits the file in place. The reviewer never changes the diff it is reading." ;;
        esac
        ;;
      find)
        case " $seg " in
          *" -exec"*|*" -execdir"*|*" -ok"*|*" -okdir"*|*" -delete"*|*" -fprintf"*|*" -fls"*|*" -fprint"*)
            deny "reviewer invariant: find -exec, -delete and the -f* actions run or write things. Locate files with find and read them separately." ;;
        esac
        ;;
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
    verb="$(sub_verb "${seg}")"

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

# Write destinations are checked before the role dispatch, because two of the
# roles that hold Write had no write branch at all: ui-designer's returned
# immediately for anything that was not Bash, and tech-writer had none. Both
# could replace a source file with Write while Edit was denied to them.
#
# The checker resolves symlinks and anchors to this project, which the lexical
# glob above cannot do - `*/docs/specs/*` matched another repository's specs
# directory just as happily as this one's.
case "$agent" in
  spec-writer|ui-designer|tech-writer|fleet-steward)
    if is_write_tool "$tool_name"; then
      if ! command -v python3 >/dev/null 2>&1; then
        log "python3 is not installed, so write-scope checking cannot run for $agent. Allowing, consistent with this hook failing open."
      else
        checker="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/check-write-scope.py"
        if [ -f "$checker" ] && ! printf '%s' "$input" | python3 "$checker"; then
          deny "$agent invariant: that write destination is outside the role's approved output scope, or the scope could not be established. spec-writer writes only under this project's docs/specs/; tech-writer writes documentation under docs/ or a Markdown file at the project root; ui-designer writes prototypes/ and a commissioned article under docs/runs/; fleet-steward writes only inside its own working copy. Name the file you need in the handoff and let the lead commission it."
        fi
      fi
    fi
    ;;
esac

case "$agent" in
  spec-writer)   enforce_spec_writer ;;
  scout)         enforce_scout ;;
  fleet-steward) enforce_fleet_steward ;;
  reviewer)      enforce_reviewer ;;
  ui-designer)   enforce_ui_designer ;;
  *)             ;;
esac

allow
