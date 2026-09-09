# Claude Code fleet review and resolution proposals

Reviewed 9 September 2026 against commit `489d655e736eb507ee4026207e478cbdf8d8613b` and the current working directory. Status: **proposed resolutions only; none applied**.

This is a review of the current definitions and plugin implementation, as requested, rather than a review against an unspecified base branch. Findings therefore describe defects present in this snapshot; they do not claim that the latest commit introduced them. The review-agent method was used without delegation. The explicit request to create this document is the sole exception to its read-only output rule.

## Findings

| ID | Priority | Finding | Primary location |
|---|---|---|---|
| R01 | P1 | Replace the shell filters that admit writes by restricted agents | `claude-agents/hooks/enforce-agent-scope.sh:149` |
| R02 | P1 | Merge managed settings without deleting unrelated host configuration | `scripts/install-home.sh:331` |
| R03 | P1 | Run the test gate in the checkout that produced the work | `claude-agents/hooks/board-task-completed.sh:54` |
| R04 | P1 | Carry the fix checkout and commit into the next review round | `claude-agents/workflows/review-round.js:296` |
| R05 | P2 | Read the documented task subject field | `claude-agents/hooks/board-task-completed.sh:52` |
| R06 | P2 | Require an explicit issue-completion task before moving an item to Done | `claude-agents/hooks/board-task-completed.sh:66` |
| R07 | P2 | Stop depending on an undocumented spawn-prompt field for board binding | `claude-agents/hooks/board-subagent-start.sh:30` |
| R08 | P2 | Enforce canonical, role-specific destinations for document writes | `claude-agents/hooks/enforce-agent-scope.sh:101` |
| R09 | P2 | Keep missing research checks from becoming verified evidence | `claude-agents/workflows/deep-research.js:264` |
| R10 | P2 | Reject invalid workflow stages before evaluating approval | `claude-agents/workflows/spec-to-plan.js:94` |
| R11 | P2 | Load the checkout under test explicitly in the eval runner | `evals/run.sh:228` |
| R12 | P2 | Fail the eval when the evaluated process fails | `evals/run.sh:232` |
| R13 | P2 | Make the requested run-article procedure available to its agents | `claude-agents/agents/reviewer.md:8` |
| R14 | P2 | Finish the interview before invoking the spec-drafting agent | `claude-agents/workflows/spec-to-plan.js:188` |

### R01 - [P1] Replace the shell filters that admit writes by restricted agents - claude-agents/hooks/enforce-agent-scope.sh:149

The hook claims to enforce read-only behaviour, but `strip_quoted` removes executable shell content before inspection. A scout command containing a substitution inside double quotes is accepted, as is a quoted `sed -n` program that writes a file. The reviewer filter also accepts `touch` outright. The steward's Bash branch only inspects selected git commands, so ordinary shell writes outside its repository are accepted. These are paths available through the agents' actual Bash allowlists, not hypothetical extra tools. A session sandbox allowing writes in the working directory or temporary directory does not enforce these role distinctions.

**Reproduced:** each of these submitted tool inputs returned exit 0 with no deny decision. The proposed shell commands themselves were not executed.

```json
{"agent_type":"scout","tool_name":"Bash","cwd":"/tmp/review","tool_input":{"command":"echo \"$(touch /tmp/fleet-review-proof)\""}}
```

```json
{"agent_type":"scout","tool_name":"Bash","cwd":"/tmp/review","tool_input":{"command":"sed -n 'w /tmp/fleet-review-proof' README.md"}}
```

```json
{"agent_type":"reviewer","tool_name":"Bash","cwd":"/tmp/review","tool_input":{"command":"touch /tmp/fleet-review-proof"}}
```

```json
{"agent_type":"fleet-steward","tool_name":"Bash","cwd":"/tmp/review","tool_input":{"command":"printf changed > /tmp/outside-repo.txt"}}
```

**Proposed resolution:** do not extend the regex blacklist and call the result a boundary. The smallest reliable containment for scout and reviewer is to remove Bash from their tools and let the lead supply git evidence. Both still have Read, Grep and Glob. This deliberately trades autonomous git inspection for an enforceable read-only role. If autonomous git is required, provide a dedicated read-only tool with fixed operations; that is additional implementation work, not something a prompt can guarantee.

Complete replacement tools line for **both** scout and reviewer:

```yaml
tools: Read, Grep, Glob, mcp__claude_ai_Memory__memory_search, mcp__claude_ai_Memory__memory_read_document, mcp__claude_ai_Memory__memory_tree, mcp__claude_ai_Memory__memory_kv_get, mcp__claude_ai_Memory__memory_kv_list
```

Replace their shell-specific body instructions with this policy, retaining their other invariants:

```text
Use Read, Grep and Glob to inspect files. The lead supplies the diff, commit IDs and any git history needed for this review. If missing git evidence prevents a conclusion, identify the exact evidence needed in the handoff. You have no shell tool and never execute repository code.
```

Replace `enforce_scout` and `enforce_reviewer` with these complete functions as a second lock:

```bash
enforce_scout() {
  if is_write_tool "$tool_name" || [ "$tool_name" = "Bash" ]; then
    deny 'scout is read-only. Use Read, Grep and Glob; ask the lead for git evidence.'
  fi
}

enforce_reviewer() {
  if is_write_tool "$tool_name" || [ "$tool_name" = "Bash" ]; then
    deny 'reviewer is read-only. Return findings; ask the lead for git evidence.'
  fi
}
```

The steward needs shell execution for its stated job, so removing Bash would not complete its resolution. Its execution should be placed in a dedicated checkout with filesystem restrictions applied to that process and no access to other working copies. Until that exists, replace the claim in `fleet-steward.md` that the hook enforces every outside-repository write with this accurate limitation:

```text
Never touch another repository. The hook restricts direct Edit destinations and some git commands; it does not contain arbitrary Bash writes. Run unattended only in a dedicated environment whose filesystem permissions restrict writes to the fleet checkout and its temporary workspace.
```

That wording is a temporary correction, not a security fix. Keep the steward portion of R01 open until the execution boundary is verified. A complete safe implementation cannot be supplied as a one-line extension to the current shell parser.

**Acceptance:** the four inputs above must be denied or contained by the appropriate process boundary; ordinary file searches must still work; a steward run must still be able to run its evals and prepare its proposal inside its allowed checkout. Test actual attempted writes only against disposable files.

### R02 - [P1] Merge managed settings without deleting unrelated host configuration - scripts/install-home.sh:331

`install_one` treats `settings.json` as an ordinary copied file. Installing the two-key repository settings object overwrites every unrelated setting, existing plugin enablement and pre-existing deny rule. The backup permits manual recovery but does not prevent the installed configuration from losing those protections and features. This is already mentioned in the untracked open-items note and remains reproducible in current code.

**Reproduced:** ran `scripts/install-home.sh --home-only` with `CLAUDE_CONFIG_DIR` and the backup directory pointing at a temporary fixture. The fixture's `model`, `enabledPlugins` and an existing deny rule all disappeared; a backup was created. No real home configuration was inspected or changed.

**Proposed resolution:** handle `settings.json` separately. Recursively merge objects; union arrays so existing denies and credential entries survive; preserve unrelated keys; let repository scalars win only where the repository supplies that key. Treat invalid JSON as an installation error. Repeated installation must be idempotent. This additive policy does not remove obsolete managed array entries automatically; removals need an explicit migration.

Complete proposed helper at `scripts/merge-settings.py`:

```python
#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def merge(existing, managed):
    if isinstance(existing, dict) and isinstance(managed, dict):
        result = dict(existing)
        for key, value in managed.items():
            result[key] = merge(result[key], value) if key in result else value
        return result
    if isinstance(existing, list) and isinstance(managed, list):
        result = list(existing)
        for value in managed:
            if value not in result:
                result.append(value)
        return result
    return managed


def read_object(path, missing_ok=False):
    if missing_ok and not path.exists():
        return {}
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f'{path}: settings must be a JSON object')
    return value


if __name__ == '__main__':
    existing_path, managed_path, output_path = map(Path, sys.argv[1:])
    existing = read_object(existing_path, missing_ok=True)
    managed = read_object(managed_path)
    Path(output_path).write_text(
        json.dumps(merge(existing, managed), indent=2) + '\n'
    )
```

Complete proposed special installer function:

```bash
install_settings() {
    local src="$1" rel="$2" dest="$CLAUDE_DIR/$2" tmp
    command -v python3 >/dev/null 2>&1 || die 'python3 is required to merge settings'
    [ ! -L "$dest" ] || die 'settings.json is a symlink; refusing to replace it automatically'
    tmp=$(mktemp "${TMPDIR:-/tmp}/fleet-settings.XXXXXX") || die 'cannot create settings temporary file'
    chmod 0600 "$tmp"
    if ! python3 "$REPO_ROOT/scripts/merge-settings.py" "$dest" "$src" "$tmp"; then
        rm -f "$tmp"
        die 'settings merge failed; existing settings were preserved'
    fi
    if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        N_UNCHANGED=$((N_UNCHANGED + 1))
        return 0
    fi
    if [ -e "$dest" ]; then
        backup_file "$dest" "$rel"
        N_UPDATED=$((N_UPDATED + 1))
    else
        N_CREATED=$((N_CREATED + 1))
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        info 'would merge settings.json, preserving unrelated settings'
        rm -f "$tmp"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    # Stage beside the destination so the final rename stays on one filesystem.
    local staged
    staged=$(mktemp "$(dirname "$dest")/.fleet-settings.XXXXXX") || {
        rm -f "$tmp"
        die 'cannot stage merged settings'
    }
    if ! cp "$tmp" "$staged" || ! chmod 0600 "$staged" || ! mv "$staged" "$dest"; then
        rm -f "$tmp" "$staged"
        die 'cannot install merged settings'
    fi
    rm -f "$tmp"
    info 'merged settings.json'
}
```

Insert this dispatch in `install_one` after its protected-path check and before its symlink/copy logic:

```bash
if [ "$rel" = 'settings.json' ]; then
    install_settings "$src" "$rel"
    return
fi
```

**Acceptance:** existing plugins, model selection, hooks and deny rules survive; repository security settings are present; a second run is unchanged; invalid input preserves the destination; dry-run changes neither destination nor backup. Also test a host overlay because the installer applies it after the base tree.

### R03 - [P1] Run the test gate in the checkout that produced the work - claude-agents/hooks/board-task-completed.sh:54

The gate prefers `CLAUDE_PROJECT_DIR` over the hook's `cwd`. When a coder operates in an isolated worktree and the project variable still names the parent checkout, tests and the default status marker are read from the parent. A passing parent can therefore approve failing work. The agent definition explicitly enables worktree isolation, so this is a fleet execution path.

**Reproduced:** the parent fixture contained a passing marker and the worktree fixture a failing marker. With hook `cwd` set to the worktree and `CLAUDE_PROJECT_DIR` set to the parent, the test command ran in the parent and the hook exited 0.

Replace the current `work_dir` selection with:

```bash
work_dir="$cwd"
if [ -z "$work_dir" ] || [ ! -d "$work_dir" ]; then
  trap - ERR
  printf 'Cannot verify completion: hook cwd is absent or unavailable.\n' >&2
  exit 2
fi
work_dir="$(cd "$work_dir" && pwd -P)"
```

This fixes a completion event emitted from the worktree. If the lead completes the issue in its own checkout, `cwd` is the lead's directory: the lead must first integrate the exact reviewed commit there and rerun verification, or the completion binding must include an independently validated worktree and commit. Do not claim that choosing `cwd` alone solves that second case.

The age-only status marker is also insufficient to establish that the current code passed: edits within its one-hour lifetime retain the old pass. The simplest complete interim change is to remove marker-based approval and require a configured test command for an explicit board completion. If markers are retained later, bind them to a checkout, commit and dirty-tree fingerprint produced by a trusted test runner.

**Acceptance:** parent pass/worktree fail must exit 2; parent fail/worktree pass must pass when the worktree is the verified target; a missing worktree must block rather than falling back to `$PWD`; a stale pass must not approve later edits.

### R04 - [P1] Carry the fix checkout and commit into the next review round - claude-agents/workflows/review-round.js:296

`coder` commits fixes in its own worktree, but the workflow merely saves its text response and increments `round`. The next mechanical and reviewer calls use the original `range` and original checkout context. Nothing records a structured fix HEAD, moves the reviewed ref, integrates the fixes, or redirects review to the fix worktree. With the documented `main...feature/refresh` invocation, later rounds inspect the unchanged feature ref and repeat the same findings. The isolated worktree can also start from a different branch unless its base is selected deliberately.

**Reproduced at the orchestration layer:** a stub coder returned a successful fix in another worktree; both reviewer prompts still requested `main...feature`. The workflow reached its round cap with the original finding. This test exercised the real script with stubbed `agent`, `parallel` and `pipeline` functions; it did not claim a live Claude workflow run.

**Proposed immediate resolution:** make a run review-only and return an explicit fix request to the lead. That avoids silently losing isolated changes and also prevents a workflow without an approved plan from spawning coder. Replace the block beginning with `// One coder` through `round += 1` with:

```javascript
  rounds[rounds.length - 1].fixRequest = {
    range,
    plan: intentPath,
    findings: blocking,
    requiresApprovedPlan: true,
  }
  stopped = 'fix handoff required'
  log(tag + ': blocking findings need an approved fix run and a new reviewed commit.')
  break
```

Replace the returned `nextStep` expression with:

```javascript
nextStep:
  stopped === 'clean'
    ? 'No blocking findings. Read the unverified checks and follow-ups before deciding whether to merge.'
    : stopped === 'fix handoff required'
      ? 'Have the lead confirm the approved plan, run coder from the reviewed commit, record the fix worktree and commit, then rerun review against that exact commit and checkout.'
      : 'The review is incomplete. Read the stop reason and resolve it before treating this run as approval.',
```

Complete proposed lead instruction for the fix handoff:

```text
Before commissioning fixes, confirm the approved plan and resolve the reviewed head to a commit. Ensure the fix checkout starts from that commit. Record the coder's resulting commit and worktree path, verify the commit contains the requested changes, and run the next review in that checkout against the recorded commit. A textual claim that fixes were committed is not a new review target. Do not merge solely to make another review possible.
```

Update the workflow's description and usage text to say it stops for a fix handoff. To preserve the automatic loop instead, introduce and validate a structured result containing `worktreePath`, `baseCommit`, `headCommit`, `testResults` and `unresolvedFindings`, then route every subsequent reader and test runner to that target. That more extensive alternative is not represented as implemented by the short replacement above.

**Acceptance:** a fixed isolated commit must be the next diff and test target; an absent commit or failed fix must stop; an unapproved or absent plan must never start coder; files introduced by a fix must be included in the next scope pass.

### R05 - [P2] Read the documented task subject field - claude-agents/hooks/board-task-completed.sh:52

The hook reads `task_title` and `task_name` but not `task_subject`. A valid completion event carrying `[board:<id>]` in its subject therefore loses its explicit binding and either updates nothing or falls back to another item. The current [TaskCompleted input reference](https://code.claude.com/docs/en/hooks#taskcompleted-input) names `task_subject`.

**Reproduced:** a completion payload with only `task_subject: "Finish [board:11111111111111111111111111111111]"` logged that no board item resolved.

Complete replacement extraction:

```bash
task_title="$(printf '%s' "$input" | jq -r '.task_subject // .task_title // .task_name // ""')"
```

Keep the older names only as compatibility fallbacks. Update the hook README, code comment and hook fixtures to use `task_subject` first.

**Acceptance:** documented subject-only payloads resolve correctly; a payload carrying conflicting subject and legacy title values uses the subject; payloads with no subject do not guess an item.

### R06 - [P2] Require an explicit issue-completion task before moving an item to Done - claude-agents/hooks/board-task-completed.sh:66

Any unmarked task can use `sessions/<session>/last-item` and close that item. The fallback does not check that there is only one item active, that the task belongs to it, or that the task represents completion of the issue. Even a single issue with twenty execution tasks can become Done after the first task. This contradicts the glossary and board skill's distinction between a native task and a tracked issue. The environment fallback has the same early-completion problem.

**Reproduced:** bound agents to items A and B, then completed an unrelated unmarked task. The hook selected B. With the default lenient gate it proceeded towards Done. The test used board-off mode and no real token.

Replace the entire board-item resolution block with:

```bash
page_id=""
if page_id="$(page_id_from_task_title "$task_title")"; then
  board_log "$HOOK" "explicit issue completion for $page_id"
else
  page_id=""
  board_log "$HOOK" "execution task has no issue-completion marker; no board transition"
fi
```

Complete replacement board/lead convention:

```text
Use [board:<page-id>] only on the one native task representing completion of the entire tracked issue. Ordinary execution tasks never carry the marker, even when they contribute to that issue. Complete the issue task only after its approved acceptance criteria and verification are satisfied. TaskCompleted does not infer issue identity from the last spawned agent or a session environment variable.
```

Unmarked tasks can still run whatever native-task gate the project wants, but `page_id` stays empty and no board transition occurs. Remove the last-item fallback from the documentation; the pointer can be retired separately once no caller needs it.

**Acceptance:** completing an unmarked task never moves A or B; completing an explicitly marked issue task moves only that item; partial implementation, scouting, review and handoff-format repair tasks cannot close the issue.

### R07 - [P2] Stop depending on an undocumented spawn-prompt field for board binding - claude-agents/hooks/board-subagent-start.sh:30

The normal binding path assumes `SubagentStart` includes `instructions`, `prompt` or `initial_prompt`. The published event contract supplies agent identity but no spawn prompt. An event conforming to that contract cannot bind the `Board-Item:` line described throughout the fleet. With no environment override, subsequent stop events have no item to update. The repository itself says this input field is not in the published schema; the review found no captured live fixture proving it is available. See the [SubagentStart input reference](https://code.claude.com/docs/en/hooks#subagentstart-input).

**Reproduced:** a documented-shape start event produced the `no board item` log. This is a verified compatibility failure for that input, not a claim that the installed CLI was observed omitting an undocumented extension.

**Proposed supported interim interface:** explicitly bind one board item per dedicated session through the existing environment variable. Keep prompt-based multi-item binding disabled until a supported correlation mechanism and real event fixtures exist. Replace lines extracting `instructions` through page resolution with:

```bash
page_id=""
source_of_id='explicit board-session environment'
if [ -n "${CLAUDE_AGENTS_BOARD_PAGE_ID:-}" ]; then
  if ! page_id="$(normalise_page_id "$CLAUDE_AGENTS_BOARD_PAGE_ID")"; then
    board_log "$HOOK" 'invalid explicit board page id; nothing moved'
    exit 0
  fi
else
  board_log "$HOOK" 'unbound session; no board item moved'
  exit 0
fi
```

Example session launch, shown for future use only:

```bash
CLAUDE_AGENTS_BOARD_PAGE_ID=11111111-1111-1111-1111-111111111111 \
  claude --agent claude-agents:lead
```

Complete replacement operational wording:

```text
A dedicated board session is bound to one item by CLAUDE_AGENTS_BOARD_PAGE_ID at launch. All delegated work in that session belongs to that item. Start unrelated work in an unbound session. Board-Item in a prompt is context for the agent, not a verified hook transport. Issue completion still requires the explicit task marker described above.
```

This narrows the supported workflow. It does not preserve the current multi-item promise, and should not be presented as doing so. Preserving that promise requires a supported adapter from the Agent tool's prompt and invocation identity to the subagent identity; do not use a shared “latest prompt” file, which recreates the race in R06.

**Acceptance:** a documented start event with an explicit environment binding records it; the stop event reads the same binding; unbound sessions do nothing; no prompt parser is required for the supported path. Capture redacted real events before restoring multi-item support.

### R08 - [P2] Enforce canonical, role-specific destinations for document writes - claude-agents/hooks/enforce-agent-scope.sh:101

The spec-writer rule accepts any path containing `/docs/specs/`, including another project's directory, and lexical normalisation does not follow existing symlinks. Meanwhile ui-designer immediately returns for non-Bash tools, and tech-writer has no hook branch at all. Both have Write, which can replace source files despite Edit being denied. Consequently the stated document/prototype-only scopes are not enforced at the actual write operation.

**Reproduced:** spec-writer Write to `/tmp/other-project/docs/specs/new.md`, ui-designer Write to this repository's `src/app.ts`, and tech-writer Write to the same source path were all accepted by the hook. No Write was executed.

**Proposed resolution:** establish trusted output paths before spawning; resolve both roots and targets physically, including existing symlink components; check each role. For tech-writer and ui-designer, explicit files avoid guessing whether a project's `.md`, `.mdx` or HTML file is documentation or executable source. Include a commissioned run-article path in the allowlist when appropriate.

Complete example checker at `hooks/lib/check-write-scope.py`:

```python
#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path


def inside(path, root):
    try:
        path.relative_to(root)
        return path != root
    except ValueError:
        return False


def main():
    event = json.load(sys.stdin)
    agent = event.get('agent_type', '')
    if agent.startswith('claude-agents:'):
        agent = agent[len('claude-agents:'):]
    if agent not in {'spec-writer', 'ui-designer', 'tech-writer', 'fleet-steward'}:
        return 0
    data = event.get('tool_input', {})
    raw = data.get('file_path') or data.get('notebook_path') or data.get('path')
    cwd = event.get('cwd')
    if not raw or not cwd:
        return 1
    project = Path(os.environ['CLAUDE_PROJECT_DIR']).resolve()
    target = Path(raw).expanduser()
    if not target.is_absolute():
        target = Path(cwd) / target
    target = target.resolve()
    if agent == 'spec-writer':
        # Anchor to the intended physical directory; reject a redirected specs root.
        root = project / 'docs' / 'specs'
        return 0 if root.resolve() == root and inside(target, root) else 1
    if agent == 'fleet-steward':
        root = Path(os.environ['CLAUDE_AGENTS_REPO']).resolve()
        return 0 if inside(target, root) else 1
    # Trusted launch configuration; this is a map from role to explicit output files.
    configured = json.loads(os.environ.get('CLAUDE_AGENTS_OUTPUT_FILES', '{}'))
    allowed = set()
    for raw_path in configured.get(agent, []):
        path = Path(raw_path).expanduser()
        if not path.is_absolute():
            path = project / path
        resolved = path.resolve()
        if inside(resolved, project):
            allowed.add(resolved)
    return 0 if target in allowed else 1


try:
    sys.exit(main())
except (KeyError, ValueError, TypeError, OSError, RuntimeError):
    sys.exit(1)
```

Call it before the current role dispatch for write tools; the checker skips other roles:

```bash
if is_write_tool "$tool_name"; then
  checker="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/check-write-scope.py"
  if ! printf '%s' "$input" | python3 "$checker"; then
    deny 'Write destination is outside this role’s approved output scope, or its scope could not be verified.'
  fi
fi
```

Example trusted output configuration:

```json
{
  "tech-writer": ["README.md", "docs/adr/001-session-refresh.md"],
  "ui-designer": ["prototypes/session-refresh.html", "docs/runs/2026-09-09-ui-designer-session-refresh.md"]
}
```

Set that JSON as `CLAUDE_AGENTS_OUTPUT_FILES` in the launching environment, not in agent-authored content. Concurrent agents needing different file lists require a binding keyed by agent identity, rather than widening one role's shared list indiscriminately. The steward's finer restriction to certain fleet files also needs a file allowlist if it is meant as enforcement, rather than prose.

This checker addresses direct file tools. It does not solve Bash writes, which remain R01, or a hostile process swapping symlinks between checking and writing. Those need filesystem containment.

**Acceptance:** permit the intended spec; reject another repo's spec, traversal and symlink escape; permit only commissioned writer/prototype files; reject source replacement through Write; missing trusted scope must deny.

### R09 - [P2] Keep missing research checks from becoming verified evidence - claude-agents/workflows/deep-research.js:264

The workflow filters null votes, then labels a claim as standing unless at least two votes refute it or two cannot verify it. One returned `refuted` vote and two failed checks therefore produce a verified claim. Two `stands` votes plus one refutation also lose the contradiction evidence in the final standing record. These are different verification lenses, so absence of evidence from one lens is not support from it.

**Reproduced:** one refutation and two nulls produced `{"stands":1,"unverifiable":0,"refuted":0}` in the real script with stubbed agent results. Null is a documented workflow result on stopped or failed agent calls. See [workflow script behaviour](https://code.claude.com/docs/en/workflows#what-the-saved-script-looks-like).

Replace the classification loop with:

```javascript
for (const j of judged.filter(Boolean)) {
  const votes = j.votes
  const negatives = votes.filter((v) => v.verdict === 'refuted')
  const positives = votes.filter((v) => v.verdict === 'stands')
  const missing = LENSES.length - votes.length
  const evidence = votes.map((v) => v.verdict + ': ' + v.why)
  if (missing > 0) evidence.push(missing + ' verification lens(es) returned no result.')

  if (negatives.length === LENSES.length) {
    refuted.push({ ...j.claim, why: evidence })
  } else if (votes.length === LENSES.length && positives.length === LENSES.length) {
    stands.push({ ...j.claim, checkedBy: votes.length, checks: votes })
  } else {
    unverifiable.push({ ...j.claim, why: evidence, checks: votes })
  }
}
```

This deliberately uses conservative unanimous verification. Mixed results become unverified and retain their reasons instead of asserting either truth or falsity. Keep the synthesis prompt's instruction to show disagreements. If a different evidence policy is preferred, define it explicitly and preserve each lens's evidence regardless.

**Acceptance:** `[refuted, null, null]`, `[stands, null, null]`, `[stands, stands, refuted]` and `[stands, stands, unverifiable]` are unverified; three stands verifies; three refutations refutes; every returned negative reason remains available to the synthesis.

### R10 - [P2] Reject invalid workflow stages before evaluating approval - claude-agents/workflows/spec-to-plan.js:94

Only literal `stage === 'plan'` is checked against spec approval. An unrecognised stage skips that guard, skips `stage === 'spec'`, and falls straight into plan generation. A typo such as `plna` therefore plans from an explicitly unapproved or missing spec.

**Reproduced:** `{issue: 'example', stage: 'plna'}` with a missing-spec gate result invoked all three planning angles, both judges and the final plan writer; the result reported `stage: 'plan'`.

Replace the stage selection and approval guard with:

```javascript
const requested = input.stage ?? 'auto'
if (!['auto', 'spec', 'plan'].includes(requested)) {
  throw new Error('stage must be auto, spec or plan')
}

// Run this part after the gate agent returns, before either stage can execute.
if (!gateResult) {
  return {
    issue,
    stage: 'blocked',
    reason: 'Approval state could not be read. No file was written.',
    nextStep: 'Resolve the failed gate check and rerun.',
  }
}
const gate = gateResult
const stage = requested === 'auto' ? (gate.specApproved ? 'plan' : 'spec') : requested
if (stage !== 'spec' && !gate.specApproved) {
  return {
    issue,
    stage: 'blocked',
    spec: specPath,
    reason: 'An approved spec is required. ' + gate.evidence,
    nextStep: 'Complete the interview and obtain approval before planning.',
  }
}
```

Move the `requested` declaration to replace the original declaration, and remove the old `gateResult || {...}` fallback. The example intentionally prevents a failed read from being treated as proof that no spec exists.

**Acceptance:** reject invalid stages before spawning; explicit plan with unapproved spec blocks; auto with draft selects spec; auto with approved spec selects plan; a null gate writes nothing.

### R11 - [P2] Load the checkout under test explicitly in the eval runner - evals/run.sh:228

The runner changes into a fixture directory and invokes bare `--agent "$agent"`. It neither loads the plugin from `REPO_ROOT/claude-agents` nor identifies the plugin-scoped agent. On a clean machine the definitions may be unavailable; on an installed machine the run can evaluate a cached or shadowing user agent instead of the changed files. Consequently a reported baseline cannot establish that the pull request's definitions were exercised.

**Verified statically:** the complete runner has no `--plugin-dir`, no local agent generation and no copying of definitions into the fixture. Project settings in `templates/` are templates, not active settings. Plugin agents have scoped identities, and local/user definitions have separate precedence; see [subagent scope](https://code.claude.com/docs/en/sub-agents#choose-the-subagent-scope).

Replace the invocation with explicit checkout loading and the scoped name:

```bash
( cd "$ws" && $TIMEOUT_CMD "$CLAUDE_BIN" \
    --plugin-dir "$REPO_ROOT/claude-agents" \
    -p "$text" "$AGENT_FLAG" "claude-agents:$agent" \
    $CLAUDE_ARGS $FORMAT_ARGS ) \
    > "$pdir/raw-output.txt" 2> "$pdir/stderr.txt"
```

The plugin loader supports temporary loading using `--plugin-dir`; see the [plugin testing reference](https://code.claude.com/docs/en/plugins-reference). Also record the checkout SHA and hashes of the nine definitions alongside the run, and test with isolated configuration so a cached copy cannot shadow it.

Complete example provenance writer, called once after creating `OUT_ROOT`:

```bash
python3 - "$REPO_ROOT" "$OUT_ROOT" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

root, output = map(Path, sys.argv[1:])
sha = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
files = {
    str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in sorted((root / 'claude-agents' / 'agents').glob('*.md'))
}
(output / 'definition-provenance.json').write_text(json.dumps({'commit': sha, 'files': files}, indent=2) + '\n')
PY
```

**Acceptance:** with no installed fleet, definitions still load from the checkout; with a deliberately stale installed fleet, the checkout is selected; modifying a definition changes the recorded hash. Retain a separate live subagent integration test: invoking a definition as the main agent does not prove all delegated-agent lifecycle, worktree and permission behaviour.

### R12 - [P2] Fail the eval when the evaluated process fails - evals/run.sh:232

The runner stores a non-zero Claude exit code but only warns. If the capture includes a valid handoff and the fixture did not change, later checks pass and the whole runner exits 0. `final-message.sh` also extracts a `result` string without rejecting `is_error: true`, so error envelopes can look like successful evidence.

**Reproduced:** a stub executable returned a valid absent-feature handoff in a JSON result with `is_error: true`, then exited 7. `evals/run.sh scout --prompt 02 --no-judge` reported both gates passing, printed “All gates passed”, and exited 0.

Immediately after capturing `rc`, add:

```bash
if [ "$rc" -ne 0 ]; then
    RUN_FAILED=1
    printf 'FAIL runtime: claude exited %s\n' "$rc" > "$pdir/runtime.txt"
else
    printf 'PASS runtime\n' > "$pdir/runtime.txt"
fi
if command -v jq >/dev/null 2>&1 && \
   jq -e -s '
     [.[] | if type == "array" then .[] else . end]
     | any(.[]; type == "object" and .type == "result" and .is_error == true)
   ' "$pdir/raw-output.txt" >/dev/null 2>&1; then
    RUN_FAILED=1
    printf 'FAIL runtime: result envelope reports is_error=true\n' > "$pdir/runtime.txt"
fi
```

In `score_prompt`, after the existing handoff/agent checks but before writing the summary row, add:

```bash
if [ -f "$pdir/runtime.txt" ] && grep -q '^FAIL ' "$pdir/runtime.txt"; then
    checks='FAIL'
    RUN_FAILED=1
fi
```

Continue extracting the partial handoff for diagnosis; do not use it to undo runtime failure. A grader failure should similarly be recorded as missing grading evidence, rather than a quality score of zero with no explanation. The documented choice to make rubric regression informational is separate and is not a finding here.

**Acceptance:** non-zero exit with valid handoff fails; `is_error: true` with exit 0 fails; timeout fails; an ordinary successful handoff still passes; summary verdict and process exit agree.

### R13 - [P2] Make the requested run-article procedure available to its agents - claude-agents/agents/reviewer.md:8

Coder, reviewer, researcher and ui-designer are told to work the run-article skill when asked, but none preloads it and none grants the Skill tool. The skill explicitly relies on discovery rather than preloading. These agents therefore cannot invoke the promised procedure through the skill mechanism. They could manually search for a file if its location were supplied, but the bodies do not define that fallback. The current [skill preloading reference](https://code.claude.com/docs/en/sub-agents#preload-skills-into-subagents) distinguishes preloading from later Skill invocation.

**Proposed resolution:** preload the small procedure into those four agents and retain its “only when asked” instruction. This avoids granting every callable skill just to enable one article procedure. Example complete reviewer skill list:

```yaml
skills:
  - glossary
  - handoff
  - review-checklist
  - using-memory
  - run-article
```

For the other three agents, append exactly the same `- run-article` entry to their existing `skills` lists. Replace the discovery claim in the skill description with:

```yaml
description: How to write a requested run article covering what was tried, abandoned and learned. Preloaded into coder, reviewer, researcher and ui-designer; used only when the spawn prompt asks for an article. Writable agents save under docs/runs and read-only agents return the article above their handoff.
```

**Acceptance:** a live loaded-context check confirms the procedure is present; a request produces the required article shape and final valid handoff; a routine run produces no article. Add an article eval that accepts commissioned `docs/runs/` output: the current ui-designer file gate rejects every `docs/` change, including this explicitly authorised deliverable.

### R14 - [P2] Finish the interview before invoking the spec-drafting agent - claude-agents/workflows/spec-to-plan.js:188

Stage one commissions a draft before its returned `nextStep` asks the lead to interview Alex. Yet `spec-writer.md` makes interviewing before any spec an absolute invariant, and the workflow cannot collect mid-run answers. The normal documented invocation therefore asks the agent to violate its definition or to refuse the workflow's principal deliverable. Labelling guesses as open questions does not resolve that ordering contradiction.

**Proposed resolution:** have the preparation workflow return the interview brief and stop. Once Alex has answered in the main session, invoke spec-writer with those answers. Keep the later approved-spec-to-plan stage.

Replace the entire `phase('Draft spec')` call and stage-one return with:

```javascript
  return {
    issue,
    stage: 'interview required',
    spec: specPath,
    questions,
    context: { decided, located, priorArt },
    nextStep:
      'Ask Alex the interview questions in the main session. Then commission spec-writer with the recorded answers to draft ' +
      specPath +
      '. Obtain approval of that spec before running the plan stage.',
  }
```

Complete subsequent spawn prompt template:

```text
Draft docs/specs/<issue>.md using the interview record below. Alex has answered these questions in the main session. Separate his explicit answers from unresolved questions; do not infer approval for an unanswered point. Write the spec with status draft and return it for Alex to edit and approve. Do not write a plan.

Interview record:
<verbatim questions and Alex's answers>

Prior decisions and repository evidence:
<verified preparation results>
```

Update the workflow metadata to name preparation, interview handoff and approved-spec planning. Preserve a guard for an empty interview brief: a failed preparation agent is not a completed interview.

**Acceptance:** preparation with no answers writes no spec; an explicit interview handoff can draft one; missing answers stay open; the plan stage requires approval; no workflow attempts to ask Alex a question mid-run.

## Validation and evidence boundaries

The following checks were completed without changing existing repository files:

| Check | Result | What it establishes |
|---|---|---|
| YAML parsing of nine agent definitions and six skill frontmatter blocks | 15 passed | Frontmatter is syntactically valid YAML |
| Bash syntax checks for repository shell scripts | Passed | Shell parsing succeeds; this does not prove semantics |
| Existing handoff parity suite | 28/28 passed | Hook and eval validators agree with the shipped fixtures |
| Glossary generator in `--check` mode | Passed | Generated rule matches the canonical skill |
| Seven scope-hook payloads | All accepted as described above | Current hook decisions admit the demonstrated operations |
| Documented task subject fixture | Binding missed | Current extraction omits `task_subject` |
| Two-item plus unrelated-task fixture | Selected most recent item | Completion fallback can target unrelated work |
| Parent/worktree verification fixture | Parent pass accepted | Test directory selection can validate the wrong checkout |
| Documented-shape SubagentStart fixture | Binding absent | Prompt-only binding does not work with the published event shape |
| Stubbed spec workflow with invalid stage | Invoked plan writer | Invalid stage bypasses the approval guard |
| Stubbed review workflow with isolated fix result | Same range reviewed twice | Script never redirects to the fix result |
| Stubbed research workflow with one refutation and two missing votes | Claim counted as standing | Incomplete checks can become verified evidence |
| Stubbed failing Claude executable through the real eval runner | Runner exited 0 | Runtime failure is not a gate |
| Installer against temporary settings and backup directories | Unrelated settings removed | The copy behaviour clobbers existing settings |

Temporary test harnesses and outputs were confined to `/tmp`. Hook tests used an empty temporary configuration and board writes disabled; no real Notion token was loaded and no Notion request was sent. The installer test used `--home-only` with a temporary `CLAUDE_CONFIG_DIR` and backup directory. No 1Password command ran. No actual Claude inference or agent delegation was run, and no paid model eval was commissioned.

The workflow harness executes the existing JavaScript body with deterministic stub results. It proves the script's branching and aggregation errors. It does not prove the native workflow loader's interpretation of `agentType`, skill resolution, worktree setup or SubagentStop timing. Those remain live integration checks before release.

The replacement snippets in this document are reviewable proposals. They were not installed or exercised as a complete revised fleet. Some deliberately narrow behaviour to provide a safe interim resolution; the tradeoffs and remaining work are stated beside them. Applying all snippets still requires integration work, updated tests and synchronised descriptions, rather than treating this document as a ready-to-apply patch file.

## Known gaps and matters not promoted to findings

- **Missing skills are already declared as forward references.** `docs/agent-contract.md:48` names the fourteen unresolved dependencies. They remain a material readiness limitation, but are not reported as newly discovered defects. A release check should distinguish required shipped procedures from intentionally deferred references.
- **Memory credentials are not separate identities today.** The contract already records that the shared connector login does not use the nine per-agent credentials as separate namespaces. No live credential configuration was inspected.
- **Failure and cancellation telemetry needs a real fixture.** `board-subagent-stop.sh:216` relies on `status` or `completion_reason` and treats unknown/missing values as success. The current published stop-event shape does not document those fields. The synthetic handoff tests insert `status: success` themselves and do not establish native failure/cancellation coverage. Do not describe those board transitions as live-verified until redacted actual events demonstrate them.
- **Structured workflow output and handoffs need an integration test.** Named fleet agents are requested with JSON schemas while the matching SubagentStop hook requires a Markdown handoff. Whether the native runtime exposes a separate structured result or the final JSON text to that hook was not established here. An isolated first-lane workflow run should settle it before any workaround is designed.
- **Installed plugin dependencies were not audited.** The open-items note says pr-review-toolkit was disabled in a previous live snapshot. That host state was not refreshed. The current reviewer prompt still assumes the mechanical pass happened; a future integration test should supply actual pass results or explicitly report their absence.
- **Unattended scheduling and CI are incomplete.** The repository has eval scripts and instructions but no checked-in CI workflow or scheduler. Baselines remain deliberately unset. The review does not interpret a planned weekly schedule or digest as an operational service.
- **Scope failure is intentionally open.** Missing jq, parse errors and some runtime errors allow calls. This is explicitly documented, so the choice itself is not labelled an accidental regression. It limits any claim that these hooks form a dependable security boundary.
- **No claim of a live secret leak.** Secret-related settings were read from the repository, not from the real home configuration. No secret values were printed. Credential-path settings and Bash restrictions still require a real sandbox integration test before being described as complete protection.

## Resolution order and completion criteria

1. Address the destructive and misleading outcomes first: R01, R02, R03 and R04. Keep unattended steward execution out of scope until its filesystem boundary exists.
2. Fix board event compatibility and ownership together: R05, R06 and R07. Explicit completion must not regress into “last agent wins”.
3. Repair file destinations and workflow decisions: R08, R09, R10 and R14.
4. Make eval provenance and runtime failures dependable: R11 and R12. Then use those evals to validate the other changes.
5. Make requested article generation available and add its dedicated eval: R13.
6. Run an isolated native Claude integration pass with synthetic data and board writes disabled. Capture redacted start, stop and task events; verify the actual loaded agent/skill identities, worktree base and output-schema behaviour. Only then run selected model smoke evals and record baselines.

Each resolution needs its specified positive and negative checks. Keep the existing 28 handoff cases and generator check. Add deterministic tests for the demonstrated hook and workflow branches, since formatting parity alone cannot detect any of the workflow failures above. Update the plugin and marketplace versions together when a corrected plugin is actually prepared for distribution.

**Overall assessment:** the role separation and handoff format are coherent enough to build on, and the existing parser fixtures are useful. The fleet is not ready to be relied on for unattended scoped execution or trustworthy board completion: several checks approve the wrong operation or the wrong evidence, and the eval runner can conceal an execution failure. The examples above make those repairs concrete while keeping all existing source and documentation untouched in this review.
