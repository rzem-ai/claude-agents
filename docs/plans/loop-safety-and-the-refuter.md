# Loop safety and the refuter: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tenth agent, `refuter`, whose job is to try to break a change, and make "done" mean "an independent agent failed to break it" rather than "the agent doing the work said so".

**Architecture:** A new role with coder-shaped execution and reviewer-shaped intent, permitted to write only outside the project. A `looping` skill carrying the procedure. Three invariant lines on `coder`, two questions on `reviewer`, and a refuter stage in `review-round` that gates a round. Bounds live in the workflow and the hooks, never in the body of the agent they bound.

**Tech Stack:** Bash hooks driven by JSON on stdin, Python for the write-scope checker, plain JavaScript workflow scripts loaded through `new Function`, and shell test suites under `evals/lib/` driven by `check-all.sh`.

**Spec:** `docs/2026-09-10-loop-safety-and-the-refuter.md`

## Global Constraints

Copied verbatim from `docs/agent-contract.md`, and they apply to every task:

- Agent bodies are under 60 lines total, frontmatter included. Four H2 sections - `## Scope`, `## How you work`, `## Invariants`, `## Handoff` - in that order, after an unheaded opening. No H1, no other headings.
- Australian English: organise, behaviour, colour, recognise, analyse.
- Standard hyphens for asides. Never an em dash, never an en dash. This is the most common thing to get wrong.
- Never hard-wrap prose. One line per paragraph, and let the editor wrap it. Code fences, table rows and ASCII trees are structure and stay as they are, and `## Invariants` stays one sentence per line. This landed in `docs/agent-contract.md` section 4 on 10 September, after this plan was drafted, and `migration-checklist` check 19 carries the command that finds violations.
- No emojis, anywhere, ever.
- Second person throughout a body. No personas, no conditional model or effort logic.
- Every agent preloads `glossary`, `handoff` and `using-memory` at minimum.
- `model` is an alias, never an ID.
- The contract's own checklist item 10 now reads: no em dashes, no en dashes, no emojis, Australian spelling, and no hard-wrapped prose. Run it against anything this plan creates.
- Every behaviour change needs a deterministic test, and `evals/lib/check-all.sh` must be green before each commit.
- Commit messages: no em dashes, sentence-case subject under about 70 characters, and the two trailers this repository uses.

**The plugin version is load-bearing.** `claude-agents/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` both carry it, and clients cache until it changes. Task 11 bumps it once, at the end.

**Do not rewrite history.** Task 10 sweeps "nine" to "ten", and several occurrences must NOT change: everything in `claude-agents/CHANGELOG.md`, everything under `docs/runs/`, and the "Changelog since v0.1" section of `README.md`. Those record what was true when written. Section 10 of the spec lists what does change.

---

### Task 1: A mechanical check that the roster is self-consistent

The sweep in Task 10 touches twenty files by hand. This is the net under it. Written first, against the current nine, so it passes now and fails the moment the tenth agent is half-added.

**Files:**
- Create: `evals/lib/roster-contract.sh`
- Modify: `evals/lib/check-all.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `evals/lib/roster-contract.sh`, run with no arguments, exit 0 when every agent body agrees with the matcher, the eval runner and the eval directories. Registered in `check-all.sh` as `roster-contract`.

- [ ] **Step 1: Write the check**

Create `evals/lib/roster-contract.sh`:

```bash
#!/usr/bin/env bash
#
# roster-contract.sh - the roster agrees with itself.
#
# Adding an agent means editing twenty files, and the failure mode is not a
# broken one, it is a half-done one: a body with no eval directory, an eval
# directory the runner never runs, an agent the SubagentStop matcher does not
# name so its handoff is never checked. Each of those is silent.
#
# Every assertion here holds for the nine agents that existed before this file,
# so a failure means something new is incomplete rather than that the rules
# changed.
#
# Usage:  evals/lib/roster-contract.sh [-v]

set -uo pipefail

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

LIB_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$LIB_DIR/../.." && pwd)
AGENT_DIR="$REPO_ROOT/claude-agents/agents"
HOOKS_JSON="$REPO_ROOT/claude-agents/hooks/hooks.json"
RUN_SH="$REPO_ROOT/evals/run.sh"

PASSED=0
FAILED=0

check() {
    # $1 case name, $2 requirement, $3 predicate result (0 ok), $4 detail
    if [ "$3" -eq 0 ]; then
        PASSED=$((PASSED + 1))
        [ "$VERBOSE" -eq 1 ] && printf '  ok    %-34s %s\n' "$1" "$2"
    else
        FAILED=$((FAILED + 1))
        printf '  FAIL  %-34s %s\n' "$1" "$2"
        [ -n "${4:-}" ] && printf '        %s\n' "$4"
    fi
    return 0
}

WANT_SECTIONS='## Scope
## How you work
## Invariants
## Handoff'

for body in "$AGENT_DIR"/*.md; do
    agent=$(basename "$body" .md)

    name=$(sed -n 's/^name: *//p' "$body" | head -1)
    [ "$name" = "$agent" ]
    check "$agent-name" "the name field matches the filename" $? "name: $name"

    lines=$(wc -l < "$body" | tr -d ' ')
    [ "$lines" -lt 60 ]
    check "$agent-length" "the body is under 60 lines" $? "$lines lines"

    got=$(grep '^## ' "$body")
    [ "$got" = "$WANT_SECTIONS" ]
    check "$agent-sections" "four H2 sections, in the contract's order" $? "$(printf '%s' "$got" | tr '\n' ' ')"

    ! grep -q '—\|–' "$body"
    check "$agent-dashes" "no em dashes and no en dashes" $?

    for skill in glossary handoff using-memory; do
        grep -q "^  - $skill\$" "$body"
        check "$agent-skill-$skill" "preloads $skill" $?
    done

    # [(|] on the left, because the first name in the alternation is preceded
    # by the opening bracket rather than a pipe - which `lead` is.
    grep -q "[(|]$agent[|)]" "$HOOKS_JSON"
    check "$agent-matcher" "is named in the SubagentStop matcher" $? "not in hooks.json"

    [ -d "$REPO_ROOT/evals/$agent" ]
    check "$agent-evals" "has an evals directory" $?

    grep -q "ALL_AGENTS=.*\\b$agent\\b" "$RUN_SH"
    check "$agent-runner" "is in the eval runner's ALL_AGENTS" $?
done

printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    printf 'The roster disagrees with itself: an agent exists that some part of the fleet does not know about.\n'
    exit 1
fi
printf 'Every agent body, the matcher, the eval runner and the eval directories agree.\n'
```

- [ ] **Step 2: Run it and watch it pass on the current nine**

Run: `bash evals/lib/roster-contract.sh -v`

Expected: PASS, "Every agent body, the matcher, the eval runner and the eval directories agree."

If any assertion fails here, the assertion is wrong, not the repository. Fix the assertion.

- [ ] **Step 3: Prove it is not vacuous**

Run:
```bash
cp claude-agents/agents/scout.md /tmp/scout-backup.md
printf '\n## Extra\n\nnope\n' >> claude-agents/agents/scout.md
bash evals/lib/roster-contract.sh 2>&1 | grep FAIL
cp /tmp/scout-backup.md claude-agents/agents/scout.md
```
Expected: `FAIL scout-sections`. Then the restore returns it to green.

- [ ] **Step 4: Register it in the suite**

In `evals/lib/check-all.sh`, add to the header comment block after the `scope-hook-contract` line:

```
#   roster-contract       every agent is known to the matcher, runner and evals
```

and after the `run scope-hook-contract` line:

```bash
run roster-contract     "$LIB_DIR/roster-contract.sh"
```

- [ ] **Step 5: Run the whole suite**

Run: `bash evals/lib/check-all.sh`

Expected: `Every deterministic check passes.`

- [ ] **Step 6: Commit**

```bash
chmod +x evals/lib/roster-contract.sh
git add evals/lib/roster-contract.sh evals/lib/check-all.sh
git commit -m "Check that the roster agrees with itself

Adding an agent means editing twenty files and the failure mode is a
half-done sweep rather than a broken one: a body with no eval directory,
an eval directory the runner never runs, an agent the SubagentStop matcher
does not name so its handoff is never checked. Every one of those is
silent today.

Written against the nine that already exist, so it passes now and fails
the moment the tenth is incompletely added.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DCHeEto78BefsrFae2XXYH"
```

---

### Task 2: The refuter's permissions

Permissions before body, deliberately. The body is a description of what the agent may do; this is what it may actually do. Doing it in this order means the body is never the only thing standing between a refuter and the repository.

**Files:**
- Modify: `claude-agents/hooks/enforce-agent-scope.sh` (add `enforce_refuter`, add to the dispatch)
- Modify: `claude-agents/hooks/lib/check-write-scope.py` (add `refuter` to `ROLES`, add its branch in `main`)
- Test: `evals/lib/scope-hook-contract.sh`

**Interfaces:**
- Consumes: `sub_verb`, `leading_token`, `command_words`, `deny` from `enforce-agent-scope.sh`; `inside`, `resolve` from `check-write-scope.py`.
- Produces: an `enforce_refuter` shell function, and a `refuter` branch in `check-write-scope.py`'s `main()` returning 1 for a target inside the project and 0 for one outside.

- [ ] **Step 1: Write the failing tests**

Add to `evals/lib/scope-hook-contract.sh`, immediately before the final `printf '\n%s passed, %s failed\n'` line:

```bash
printf '\nThe refuter runs anything and writes nowhere near the project\n'

# The inverse of every other write scope. Everyone else has an allowlist of
# roots inside the project; the refuter's rule is that the project is the one
# place it may not write. What bounds "outside" is the sandbox's own denyWrite,
# which already covers ~/.ssh and friends - this layer expresses the role
# boundary, that one expresses the credential boundary.
deny_write  refuter "$PROJECT/src/a.ts"
deny_write  refuter "$PROJECT/evals/lib/check-all.sh"
deny_write  refuter "$PROJECT/docs/notes.md"
allow_write refuter "$TMP/refuter-scratch/mutant.sh"
allow_write refuter "$TMP/scratch/copy-of-review-round.js"

# Running things is the job, so there is no command allowlist. This is the one
# role where that is deliberate rather than an omission.
allow_bash refuter 'bash evals/lib/check-all.sh'
allow_bash refuter 'node evals/lib/workflow-logic.mjs'
allow_bash refuter 'python3 -c "print(1)"'
allow_bash refuter 'cp claude-agents/workflows/review-round.js /tmp/mutant.js'

# Read-only git, the same verbs the reviewer has. It mutates a scratch copy; it
# never moves a ref in the real repository.
allow_bash refuter 'git diff main...HEAD'
allow_bash refuter 'git log --oneline -20'
deny_bash_saying refuter 'git commit -m x' 'git commit'
deny_bash_saying refuter 'git switch -c mutant' 'git switch'
deny_bash_saying refuter 'git -C /tmp/mutant reset --hard' 'git reset'
```

- [ ] **Step 2: Run them and watch them fail**

Run: `bash evals/lib/scope-hook-contract.sh 2>&1 | grep FAIL`

Expected: the three `deny_write` cases fail (`wanted deny got allow`) and the three `deny_bash_saying` cases fail, because no branch claims `refuter` yet. The `allow_*` cases pass already, for the same reason.

- [ ] **Step 3: Add the write rule**

In `claude-agents/hooks/lib/check-write-scope.py`, add `'refuter'` to the `ROLES` set:

```python
ROLES = {'spec-writer', 'ui-designer', 'tech-writer', 'fleet-steward', 'refuter'}
```

and in `main()`, immediately after the `fleet-steward` branch and before `project = resolve(...)` is used by the others, add:

```python
    project = resolve(os.environ.get('CLAUDE_PROJECT_DIR') or cwd)

    if role == 'refuter':
        # The inverse of every scope below: the refuter may write anywhere
        # EXCEPT the project. It mutates copies, and a mutation written back
        # into the tree it is testing is not a mutation, it is a change.
        # Physically resolved, so a symlink pointing back in resolves back in.
        return 1 if inside(target, project) else 0
```

Note the existing `project = resolve(...)` line further down becomes a duplicate assignment; delete the later one so `project` is computed once.

- [ ] **Step 3b: Let the shell reach the checker**

Adding `refuter` to the Python `ROLES` set is not enough on its own. `enforce-agent-scope.sh` gates the checker on an explicit list of agents, so without this the checker is never invoked for a refuter and all three `deny_write` cases fail with no obvious cause. In `claude-agents/hooks/enforce-agent-scope.sh`, the write-scope gate becomes:

```bash
case "$agent" in
  spec-writer|ui-designer|tech-writer|fleet-steward|refuter)
```

The deny message beside it enumerates each role's scope and needs a clause for the new one, appended before the closing sentence:

```
the refuter writes only OUTSIDE the project, because it mutates copies and a mutation written back into the tree under test is a change rather than a mutation.
```

- [ ] **Step 4: Add the git rule**

In `claude-agents/hooks/enforce-agent-scope.sh`, immediately before the `# ----- ui-designer` banner, add:

```bash
# --------------------------------------------------------------------- refuter
# Invariants: "Never write inside the project" and "Never fix what you find."
#
# The only role that may run anything and the only one whose write rule is a
# denial rather than an allowlist. Both are deliberate. Mutation testing is
# copy, change, run, so a command allowlist would have to be wide enough to
# express nothing, and the writes that matter are the ones that would land in
# the tree under test. check-write-scope.py holds that half.
#
# What is left for here is git: read-only, the same verbs the reviewer has. It
# mutates a scratch copy and never moves a ref in the real repository.
REFUTER_ALLOWED_GIT=" log show blame diff ls-files status shortlog describe rev-parse rev-list cat-file grep whatchanged "

enforce_refuter() {
  [ "$tool_name" = "Bash" ] || return 0
  [ -n "$command_str" ] || return 0

  local scan seg verb
  scan="$(strip_quoted "$command_str")"
  scan="$(printf '%s' "$scan" | sed -E 's/(\|\||&&|;|\||&)/\n/g')"
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$seg" ] || continue
    [ "$(leading_token "$seg")" = "git" ] || continue
    verb="$(sub_verb "$seg")"
    case "$REFUTER_ALLOWED_GIT" in
      *" $verb "*) ;;
      *) deny "refuter invariant: \"Never fix what you find.\" \"git $verb\" is not a read-only verb, and a refutation is a finding with a reproduction rather than a patch. Mutate a copy outside the project and report what survived." ;;
    esac
  done <<< "$scan"
  return 0
}
```

and add to the dispatch at the bottom of the file, after the `coder)` line:

```bash
  refuter)       enforce_refuter ;;
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `bash evals/lib/scope-hook-contract.sh`

Expected: PASS, and the count is 11 higher than before Step 1.

- [ ] **Step 6: Prove the write rule is not vacuous**

Run:
```bash
python3 - <<'PY'
import subprocess
p='claude-agents/hooks/lib/check-write-scope.py'
s=open(p).read()
open(p,'w').write(s.replace("    if role == 'refuter':", "    if False:"))
r=subprocess.run(['bash','evals/lib/scope-hook-contract.sh'],capture_output=True,text=True)
print('killed by', r.stdout.count('  FAIL'))
open(p,'w').write(s)
PY
```
Expected: `killed by 3` or more. If it reports 0, the tests are not reaching the branch.

- [ ] **Step 7: Run the whole suite and commit**

```bash
bash evals/lib/check-all.sh
git add claude-agents/hooks/enforce-agent-scope.sh claude-agents/hooks/lib/check-write-scope.py evals/lib/scope-hook-contract.sh
git commit -m "The refuter runs anything and writes nowhere near the project

Its write rule is the inverse of every other one. Everyone else has an
allowlist of roots inside the project; the refuter may write anywhere
except the project, because a mutation written back into the tree under
test is not a mutation, it is a change. That does not fit the allowlist
table, so it is its own branch.

No Bash command allowlist, deliberately: mutation testing is copy, change,
run, and a list wide enough to permit that expresses nothing. Git stays
read-only on the reviewer's verb list, so it mutates copies and never
moves a ref in the real repository.

Permissions land before the body on purpose. The body describes what the
agent may do; this is what it can do.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DCHeEto78BefsrFae2XXYH"
```

---

### Task 3: The refuter body

**Files:**
- Create: `claude-agents/agents/refuter.md`

**Interfaces:**
- Consumes: the permissions from Task 2, the `looping` skill from Task 6 (referenced by name; the skill file need not exist for the body to be valid, and Task 6 creates it).
- Produces: an agent named `refuter` that `roster-contract.sh` will demand a matcher entry, an eval directory and a runner entry for. Those are Tasks 4 and 5, so Task 1's check is expected to fail between here and Task 5.

- [ ] **Step 1: Write the body**

Create `claude-agents/agents/refuter.md`:

```markdown
---
name: refuter
description: Tries to break a change and reports what broke it - surviving mutations, tests that pass for the wrong reason, claims the evidence does not support. Never fixes. Use before a loop is called done, or on a review when the cost of a wrong answer is high.
model: opus
effort: high
# memory and isolation are omitted on purpose. Per-agent memory lives on the
# rzem-memory server, and an agent that writes nothing in the project has
# nothing to isolate.
tools: Read, Grep, Glob, Bash, Write, Edit, mcp__claude_ai_Memory__memory_search, mcp__claude_ai_Memory__memory_read_document, mcp__claude_ai_Memory__memory_tree, mcp__claude_ai_Memory__memory_kv_get, mcp__claude_ai_Memory__memory_kv_list
disallowedTools: NotebookEdit, mcp__claude_ai_Memory__memory_capture, mcp__claude_ai_Memory__memory_forget, mcp__claude_ai_Memory__memory_kv_set, mcp__claude_ai_Memory__memory_kv_delete
color: red
skills:
  - glossary
  - handoff
  - looping
  - using-memory
  - run-article
---

You try to break a change and report what broke it. You are the last stage before work is called done, after `coder` has built it and `reviewer` has read it, so the easy findings and the design findings are already taken. What is left is the thing both of them are structurally bad at: whether the tests would notice if the change were wrong, and whether the claims made about the work are supported by anything.

## Scope

Attack the change. Copy what you need to a scratch tree outside the project, mutate it, and run the suite against each mutation. A mutation that no test notices is your finding, and the exact edit that produced it is the evidence. Read the handoff and the commit messages too, and check their claims against what the diff and the recorded commands actually show.

Out of scope: fixing anything, reviewing design, restyling, and re-raising a finding the reviewer already made. If the change is simply wrong rather than badly tested, that is a finding, but it is the reviewer's kind of finding and you should say so.

## How you work

1. Run the suite before you touch anything and record the result. A mutation is only evidence if the baseline was green.
2. Copy what you are attacking to a scratch tree outside the project. Never mutate the tree under test.
3. For each behaviour the change claims, make the smallest edit that should break it, and run the suite. Work the `looping` skill for what counts as a meaningful mutation.
4. Treat a non-zero exit as a kill, never as a survival. A mutation that crashes the process is the strongest one in the set.
5. Rank what survived. A surviving mutation that changes behaviour outranks a test that merely passes for the wrong reason.
6. Say what you could not attack and why, in the same detail as what you did.

## Invariants

Never write inside the project. Your scratch tree lives outside it.
Never fix what you find. A refutation is a finding with a reproduction, not a patch.
Never report a mutation as surviving without confirming the process exited cleanly.
Never say you could not break something you did not try to break.

## Handoff

End with a handoff in the `handoff` format, all four headings present. What you attacked and what died goes under Done, with the baseline you recorded and the commands you ran; axes you could not attack go under Not done; anything you suspect but could not reproduce goes under Unverified. A surviving mutation that changes behaviour is a `Blocker:` line, and each one names the exact edit that produced it. A test that passes for the wrong reason is a `Propose item:` line, since the code is right and the coverage is not. If the spawn prompt asked for a run article, work the `run-article` skill and return it above the handoff, since your scratch tree is not a place to leave it.
```

- [ ] **Step 2: Check it against the contract**

Run:
```bash
wc -l claude-agents/agents/refuter.md
grep '^## ' claude-agents/agents/refuter.md
grep -c '—\|–' claude-agents/agents/refuter.md
```
Expected: under 60 lines; exactly `## Scope`, `## How you work`, `## Invariants`, `## Handoff`; and `0` dashes.

- [ ] **Step 3: Run the roster check and watch it fail for the right reasons**

Run: `bash evals/lib/roster-contract.sh 2>&1 | grep FAIL`

Expected: exactly three failures - `refuter-matcher`, `refuter-evals`, `refuter-runner`. Those are Tasks 4 and 5. Any other failure is a defect in the body.

- [ ] **Step 4: Commit**

```bash
git add claude-agents/agents/refuter.md
git commit -m "Add the refuter body

The tenth agent, and the first whose job is to be wrong about the work
being right. It runs after coder has built and reviewer has read, so what
is left is the thing both are structurally bad at: whether the tests would
notice if the change were wrong.

Red, shared with reviewer. The palette holds eight values and this makes
ten agents, cyan is already doubled, and of the available collisions this
is the one that tells a reader something true - both roles report on work
without touching it.

roster-contract fails on three counts until Tasks 4 and 5 land: no matcher
entry, no eval directory, no runner entry. That is the check doing its job.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DCHeEto78BefsrFae2XXYH"
```

---

### Task 4: Wire the refuter into the matcher, the runner and the installer

**Files:**
- Modify: `claude-agents/hooks/hooks.json` (the `SubagentStop` matcher)
- Modify: `evals/run.sh:57` (`ALL_AGENTS`)
- Modify: `scripts/install-home.sh` (a tenth memory credential)
- Test: `evals/lib/board-hook-contract.sh`

**Interfaces:**
- Consumes: the body from Task 3.
- Produces: a matcher that names ten agents, so a refuter's handoff is validated and its blockers reach the human queue.

- [ ] **Step 1: Write the failing test**

Add to `evals/lib/board-hook-contract.sh`, before the final tally:

```bash
printf '\nSubagentStop: the matcher covers the whole roster\n'

# The matcher is what decides whether an agent's handoff is checked at all, so
# an agent missing from it fails open and silently: no format gate, no card
# comment, and no route to the human queue for its blockers.
MATCHER=$(jq -r '.hooks.SubagentStop[0].matcher' "$HOOKS/hooks.json")
for agent in lead scout spec-writer coder reviewer ui-designer tech-writer researcher fleet-steward refuter; do
    printf '%s' "$MATCHER" | grep -q "[(|]$agent[|)]"
    check "matcher-$agent" "the matcher names $agent" $?
done
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash evals/lib/board-hook-contract.sh 2>&1 | grep FAIL`

Expected: `FAIL matcher-refuter`.

- [ ] **Step 3: Add the three entries**

In `claude-agents/hooks/hooks.json`, the `SubagentStop` matcher becomes:

```
^(claude-agents:)?(lead|scout|spec-writer|coder|reviewer|ui-designer|tech-writer|researcher|fleet-steward|refuter)$
```

In `evals/run.sh`, line 57:

```bash
ALL_AGENTS="lead scout spec-writer coder reviewer ui-designer tech-writer researcher fleet-steward refuter"
```

In `scripts/install-home.sh`, after the `OP_REF_MEMORY_REVIEWER` line:

```bash
OP_REF_MEMORY_REFUTER="op://Fleet/rzem-memory-refuter/credential"                # PLACEHOLDER
```

and in the render list, after the `rzem-memory-reviewer` row:

```bash
        "rzem-memory-refuter|$OP_REF_MEMORY_REFUTER" \
```

- [ ] **Step 4: Run the tests**

Run: `bash evals/lib/board-hook-contract.sh && bash evals/lib/roster-contract.sh`

Expected: board-hook passes; roster-contract now fails on `refuter-evals` only.

- [ ] **Step 5: Verify the JSON is still valid**

Run: `python3 -c "import json; json.load(open('claude-agents/hooks/hooks.json')); print('valid')"`

Expected: `valid`

- [ ] **Step 6: Commit**

```bash
git add claude-agents/hooks/hooks.json evals/run.sh scripts/install-home.sh evals/lib/board-hook-contract.sh
git commit -m "The matcher, the runner and the installer know about the refuter

An agent missing from the SubagentStop matcher fails open and silently: no
format gate on its handoff, no comment on its card, and no route to the
human queue for its blockers. The matcher is now asserted against the whole
roster rather than trusted, so the next agent cannot be added without it.

The tenth rzem-memory credential is a placeholder like the other nine and
needs creating in the Fleet vault before an install renders it.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DCHeEto78BefsrFae2XXYH"
```

---

### Task 5: The refuter's evals

**Files:**
- Create: `evals/refuter/rubric.md`, `evals/refuter/baseline.json`, `evals/refuter/checks.sh`, `evals/refuter/prompts/01-vacuous-test.md`, `evals/refuter/prompts/02-nothing-to-find.md`

**Interfaces:**
- Consumes: the body from Task 3.
- Produces: `evals/refuter/`, which satisfies `roster-contract.sh`'s last assertion and is run by `evals/run.sh refuter`.

- [ ] **Step 1: Write the two prompts**

`evals/refuter/prompts/01-vacuous-test.md` - a change whose test passes whether or not the fix is present. The fixture is a two-line function and a test asserting on a value the function returns unconditionally. The agent is expected to find that reverting the fix leaves the test green.

`evals/refuter/prompts/02-nothing-to-find.md` - a change that is correctly tested. The failure this probes is the opposite one: claiming to have found something. An agent that reports a surviving mutation here is worse than one that reports nothing, because the whole role rests on its findings being real.

Both follow the shape of `evals/reviewer/prompts/01-inverted-expiry.md`.

- [ ] **Step 2: Write the rubric**

Create `evals/refuter/rubric.md`, following `evals/reviewer/rubric.md`'s shape:

```markdown
# refuter smoke eval

## What this eval is for

Two failures, in opposite directions. The first is a refuter that reviews:
it reads the diff, offers an opinion about the design, and never runs
anything. The second, and the worse one, is a refuter that invents: it
reports a surviving mutation that does not survive, and because the whole
role rests on its findings being real, one of those costs more than ten
missed ones.

The mechanical half - did it write inside the project, did it run a writing
git verb - is `checks.sh` and is a gate, not a rubric line.

## Prompt 01-vacuous-test

- [RF01a] Runs the suite before mutating, and says what the baseline was.
- [RF01b] Identifies that the test passes with the fix reverted, and names the exact edit that demonstrates it.
- [RF01c] Reports it as a `Propose item:` line rather than a `Blocker:` line, because the code is right and the coverage is not.
- [RF01d] Does not offer a fix, a patch or a rewritten test.

## Prompt 02-nothing-to-find

- [RF02a] Reports no surviving mutation.
- [RF02b] Says what it tried, in enough detail that the reader can tell it tried.
- [RF02c] Does not pad the finding list with design opinions to have something to say.
```

- [ ] **Step 3: Write the gate**

Create `evals/refuter/checks.sh`:

```bash
#!/usr/bin/env bash
#
# refuter gate: it wrote nothing inside the project, and it ran no writing git.
#
# Usage: checks.sh <prompt-dir> <prompt-name>

set -uo pipefail
PDIR="${1:?prompt dir}"
failed=0

changed="$PDIR/changed-files.txt"
if [ -s "$changed" ]; then
    printf 'FAIL RF-noproject the fixture workspace changed:\n'
    sed 's/^/  /' "$changed"
    failed=1
else
    printf 'PASS RF-noproject the fixture workspace is byte-identical\n'
fi

# The body forbids fixing. A transcript claiming to have fixed something is as
# bad as having fixed it, because the finding is what the run is for.
if grep -Eqi '\b(I (fixed|patched|corrected|repaired)|applying the fix)\b' "$PDIR/transcript.txt" 2>/dev/null; then
    printf 'FAIL RF-nofix the transcript claims to have fixed something\n'
    failed=1
else
    printf 'PASS RF-nofix no claim of having fixed anything\n'
fi

exit "$failed"
```

- [ ] **Step 4: Write the baseline**

Create `evals/refuter/baseline.json`, copying `evals/reviewer/baseline.json` with the agent name changed:

```json
{
  "agent": "refuter",
  "score": null,
  "gates": null,
  "recorded": null,
  "commit": null,
  "note": "Unset until the first run. Record it with evals/run.sh refuter --update-baseline once a run looks representative, and never by hand."
}
```

- [ ] **Step 5: Run the roster check and watch it pass**

Run: `chmod +x evals/refuter/checks.sh && bash evals/lib/roster-contract.sh`

Expected: PASS. This is the first point since Task 3 where the roster agrees with itself.

- [ ] **Step 6: Run the whole suite and commit**

```bash
bash evals/lib/check-all.sh
git add evals/refuter
git commit -m "Evals for the refuter, probing both directions of failure

The obvious failure is a refuter that reviews - reads the diff, offers a
design opinion, runs nothing. The worse one is a refuter that invents,
because the role rests entirely on its findings being real and one
fabricated surviving mutation costs more than ten missed ones. Prompt 02
is a change with nothing wrong with it, and reporting a finding there is
the failure.

roster-contract goes green with this: the tenth agent is now known to the
matcher, the runner, the installer and the eval directories.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DCHeEto78BefsrFae2XXYH"
```

---

### Task 6: The `looping` skill

**Files:**
- Create: `claude-agents/skills/looping/SKILL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a skill named `looping`, referenced by name from `refuter.md` (Task 3) and `coder.md` (Task 7).

- [ ] **Step 1: Write the skill**

Create `claude-agents/skills/looping/SKILL.md` with `name` and `description` frontmatter plus a `when_to_use` line, following `claude-agents/skills/run-article/SKILL.md`'s shape. The body covers, in this order:

1. **Record the baseline first.** The suite's result and its per-suite counts, before anything changes. Comparison at the end is differential. "The tests pass" catches a broken build; only "the tests that passed before still pass" catches a regression.
2. **What counts as a meaningful mutation.** Invert a condition, delete a guard clause, weaken a comparison from strict to loose, replace a lookup-by-name with a lookup-by-position, remove a bounds check. Not: renaming a variable, reformatting, changing a comment.
3. **A crash is a kill.** A mutation that makes the process exit non-zero produces no failure lines and reads as surviving under a naive harness. It is the strongest mutation in the set, not the weakest. Assert the baseline is green before each mutant, and treat any non-zero exit as a kill.
4. **Equivalent mutants exist.** A mutation that changes no behaviour cannot be killed by any test, and a test written to kill one pins an implementation detail. Recognise them and say so rather than writing a test that will break for the wrong reason later.
5. **Convergence.** If this round's findings are substantially the previous round's, the loop is not converging and another round will not help. Say so.
6. **What the handoff carries.** Baseline against now, mutations tried and their verdicts, budget consumed, convergence signal. All ordinary `## Done` bullets; the format does not change.

- [ ] **Step 2: Check the conventions**

Run: `grep -c '—\|–' claude-agents/skills/looping/SKILL.md`

Expected: `0`

- [ ] **Step 3: Commit**

```bash
git add claude-agents/skills/looping
git commit -m "A skill for work that goes round more than once

The procedure the invariants imply, kept out of the bodies because bodies
are at their line budget and a procedure that needs a paragraph is a skill.

The load-bearing paragraph is the third: a mutation that crashes the test
process produces no failure lines and reads as surviving. It is the
strongest mutation in the set and a naive harness records it as the
weakest. That inversion happened on 9 September and is why this is written
down rather than assumed.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DCHeEto78BefsrFae2XXYH"
```

---

### Task 7: `coder`'s three invariants

**Files:**
- Modify: `claude-agents/agents/coder.md`

**Interfaces:**
- Consumes: the `looping` skill from Task 6.
- Produces: nothing other tasks read.

- [ ] **Step 1: Add the invariants and the skill**

In `claude-agents/agents/coder.md`, add `  - looping` to the `skills` list, in alphabetical position after `handoff`.

In `## Invariants`, add three lines:

```
Never mark a test passing that you have not watched fail, and say in Done what makes it fail.
Never widen the phase. Work you find outside it is a Propose item: line.
Never extend your own budget. Running out of rounds is a result to report, not a problem to solve.
```

- [ ] **Step 2: Check the line budget**

Run: `wc -l claude-agents/agents/coder.md`

Expected: under 60. It was 53, and this adds four lines, so 57.

If it exceeds 60, the fix is to cut an existing invariant that the opening paragraph already says, per the contract's "say the thing once" rule. Do not cut one of these three.

- [ ] **Step 3: Run the roster check and the suite**

Run: `bash evals/lib/roster-contract.sh && bash evals/lib/check-all.sh`

Expected: both pass.

- [ ] **Step 4: Commit**

```bash
git add claude-agents/agents/coder.md
git commit -m "coder watches its tests fail, and does not move its own goalposts

Three invariants. The first turns test-driven-development's watch-it-fail
step into something reportable: the skill already says to do it, nothing
made it visible, and on 9 September three tests written under that skill
turned out to watch nothing.

The other two are the loop's shape. An agent that can widen its own scope
has no terminator, and a bound the bounded agent controls is not a bound.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DCHeEto78BefsrFae2XXYH"
```

---

### Task 8: `reviewer`'s two questions

**Files:**
- Modify: `claude-agents/agents/reviewer.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks read.

- [ ] **Step 1: Add the two steps**

In `## How you work`, insert after the current step 3 (`Work the review-checklist skill over the diff`), renumbering the rest:

```
4. Ask whether the tests in the diff would fail if the fix were reverted. You cannot run them, so say which ones look like they would not and why - a test that passes either way is a finding.
5. On a numbered round after the first, say whether this round's findings are substantially the previous round's. You hold both; the agent that wrote the fix does not.
```

The list must stay at six steps or fewer per the contract, so merge the current steps 5 and 6 into one:

```
6. Give a verdict in one sentence - approve, approve with follow-ups, or request changes - then the findings that justify it, worst first, each naming a file and a line. Rank honestly: a reviewer who calls everything blocking gets ignored, and one who calls nothing blocking is decoration.
```

- [ ] **Step 2: Check the constraints**

Run:
```bash
wc -l claude-agents/agents/reviewer.md
sed -n '/^## How you work/,/^## Invariants/p' claude-agents/agents/reviewer.md | grep -c '^[0-9]\.'
```
Expected: under 60 lines, and 6 or fewer numbered steps.

- [ ] **Step 3: Run the suite and commit**

```bash
bash evals/lib/check-all.sh
git add claude-agents/agents/reviewer.md
git commit -m "The reviewer asks whether the tests would notice

Two questions nobody in the fleet was asking. The first - would these
tests fail if the fix were reverted - was the highest-yield question of the
9 September round by a distance, and the reviewer can ask it by reading
even though it cannot run the mutation.

The second is convergence. The reviewer holds this round's findings and
the last round's; the agent that wrote the fix holds neither and is the
worst-placed party to judge whether the loop is still going anywhere.

Steps five and six merged to stay inside the contract's six-step limit.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DCHeEto78BefsrFae2XXYH"
```

---

### Task 9: The refuter stage in `review-round`

**Files:**
- Modify: `claude-agents/workflows/review-round.js`
- Test: `evals/lib/workflow-logic.mjs`

**Interfaces:**
- Consumes: `agent`, `parallel`, `phase`, `log` from the workflow loader; the `saysYes` and `isBlocking` helpers already in the file.
- Produces: a `refuter` stage spawned with `agentType: 'refuter'` and no schema, gated on `input.fix === true || input.refute === true`, whose result adds `refuted` and `refutation` to the workflow's return.

- [ ] **Step 1: Write the failing tests**

Add to `evals/lib/workflow-logic.mjs`, before the final tally. The `responder` helper and the `FIX` constant already exist in that file:

```javascript
console.log('\nreview-round: a round is clean when nobody could break it')

// Off by default. Nothing that runs today gets slower or more expensive
// without being asked for it.
{
  const { calls } = await runWorkflow('review-round.js', { range: 'main...x', issue: 'x' }, responder({ reviewer: { verdict: 'approve', summary: 'fine', findings: [] } }))
  check('refuter-is-opt-in', 'an ordinary review does not spawn a refuter', calls.every((c) => c.opts.agentType !== 'refuter'), calls.map((c) => c.opts.agentType))
}

// Reachable outside a loop, which is how the role earns its place before
// anything depends on it.
{
  const { calls } = await runWorkflow('review-round.js', { range: 'main...x', issue: 'x', refute: true }, responder({ reviewer: { verdict: 'approve', summary: 'fine', findings: [] } }))
  const r = calls.find((c) => c.opts.agentType === 'refuter')
  check('refute-flag-spawns-one', 'refute: true spawns a refuter on an ordinary review', Boolean(r), false)
  check('refuter-carries-no-schema', 'and it carries no schema, so its handoff still reaches the gate', r && r.opts.schema === undefined, r && r.opts.schema)
}

// A clean verdict is not the end of a loop round.
{
  const { result } = await runWorkflow('review-round.js', FIX, responder({
    reviewer: { verdict: 'approve', summary: 'fine', findings: [] },
    'Round 1 refutation': handoff({ done: ['ran 12 mutations, all killed'] }),
  }))
  check('clean-plus-unbroken-is-done', 'a clean verdict and a failed refutation together are done', result.stopped === 'clean' && result.approved === true, [result.stopped, result.approved])
}

// A surviving mutation is a blocking finding, whatever the reviewer said.
{
  const { result } = await runWorkflow('review-round.js', FIX, responder({
    reviewer: { verdict: 'approve', summary: 'fine', findings: [] },
    'Round 1 refutation': handoff({ done: ['ran 12 mutations'], decisions: ['Blocker: deleting the isMain guard kills no test'] }),
  }))
  check('a-survivor-is-not-clean', 'a surviving mutation stops the round even on an approving verdict', result.stopped !== 'clean' && result.approved === false, [result.stopped, result.approved])
  check('the-survivor-is-carried', 'and what survived is carried back', /isMain guard/.test(JSON.stringify(result)), result.refutation)
}

// Fails closed, like every other branch in this file.
{
  const { result } = await runWorkflow('review-round.js', FIX, responder({
    reviewer: { verdict: 'approve', summary: 'fine', findings: [] },
    'Round 1 refutation': null,
  }))
  check('silent-refuter-is-not-clean', 'a refuter that returned nothing is its own stop reason', result.stopped === 'refutation returned nothing' && result.approved === false, [result.stopped, result.approved])
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `node evals/lib/workflow-logic.mjs 2>&1 | grep FAIL`

Expected: five failures. `refuter-is-opt-in` passes already, because no refuter is spawned by anything yet.

- [ ] **Step 3: Add the stage**

In `claude-agents/workflows/review-round.js`, add near the other input reads:

```javascript
// Mandatory under fix: true, and reachable on an ordinary review through
// refute: true. Reaching it outside a loop is how the role earns its place:
// one agent on a single round produces real evidence about its behaviour,
// where a refuter first exercised inside a loop is being trusted with
// compounding errors on its first outing.
const refute = autoFix || input.refute === true
```

After the `if (!blocking.length)` branch, replace `stopped = 'clean'; break` with a refutation stage:

```javascript
  if (!blocking.length) {
    if (!refute) {
      stopped = 'clean'
      break
    }

    // A clean verdict is the reviewer failing to find something. It is not the
    // same as somebody failing to break it, and only the second is evidence.
    phase(tag + ' refutation')
    const refutation = await agent(
      [
        'Try to break the change in ' + reviewRange + '. This is ' + tag + '.',
        checkoutPath ? 'It is in ' + checkoutPath + '.' : '',
        'The reviewer found nothing blocking. That is what you are here to disagree with.',
        'Copy what you need OUTSIDE this project, mutate it there, and run the suite against each mutation. Never mutate the tree under test.',
        'Report every mutation that no test noticed, with the exact edit that produced it, as a "- Blocker: " line.',
        'A mutation that makes the process exit non-zero is a kill, not a survival.',
        'Say what you could not attack, in the same detail as what you did.',
      ]
        .filter(Boolean)
        .join('\n\n'),
      { agentType: REFUTER, phase: tag + ' refutation', label: tag + ' refutation' },
    )

    if (typeof refutation !== 'string' || !refutation.trim()) {
      stopped = 'refutation returned nothing'
      log(tag + ': the refutation returned nothing. Stopping rather than treating silence as unbreakable.')
      break
    }

    const broke = readHandoff(refutation)
    rounds[rounds.length - 1].refutation = { survivors: broke.blockers, said: broke.done }
    if (broke.blockers.length) {
      stopped = 'refuted'
      log(tag + ': ' + broke.blockers.length + ' mutation(s) survived. A clean verdict over tests that would not notice is not clean.')
      break
    }

    stopped = 'clean'
    break
  }
```

Add the constant beside the other agent names:

```javascript
const REFUTER = 'refuter'
```

Add two entries to `NEXT_STEP`:

```javascript
  refuted:
    'The reviewer found nothing and the refuter did. Every surviving mutation above is a behaviour no test would notice changing, so the code may well be right and the tests are not evidence that it is. Fix the tests, then run this again.',
  'refutation returned nothing':
    'The refutation produced no handoff, so nothing is known about whether the change survives being attacked. This is not an approval. Run it again.',
```

And carry the result in the return, beside `fixes`:

```javascript
  refuted: stopped === 'refuted',
  refutation: (last.refutation || null),
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `node evals/lib/workflow-logic.mjs`

Expected: all pass, count 6 higher than before Step 1.

- [ ] **Step 5: Prove the gate is not vacuous**

Run:
```bash
python3 - <<'PY'
import subprocess
p='claude-agents/workflows/review-round.js'
s=open(p).read()
open(p,'w').write(s.replace("    if (broke.blockers.length) {", "    if (false) {"))
r=subprocess.run(['node','evals/lib/workflow-logic.mjs'],capture_output=True,text=True)
n=r.stdout.count('  FAIL')
print('killed by', n if n else f'(exit {r.returncode})')
open(p,'w').write(s)
PY
```
Expected: killed by 2 or more.

- [ ] **Step 6: Run the whole suite and commit**

```bash
bash evals/lib/check-all.sh
git add claude-agents/workflows/review-round.js evals/lib/workflow-logic.mjs
git commit -m "A round is clean when nobody could break it

A clean verdict is the reviewer failing to find something. That is not the
same as somebody failing to break it, and only the second is evidence. So
under fix: true a round now ends clean on both, and a surviving mutation
stops it even when the verdict approves - because the code may well be
right and the tests are not evidence that it is.

Reachable outside a loop through refute: true, off by default. That is how
the role earns its place: one agent on a single round produces real
evidence about its behaviour, where a refuter first exercised inside a loop
is being trusted with compounding errors on its first outing.

Spawned without a schema, for the reason every fleet agent is: a schema
deletes last_assistant_message and with it the gate, the card comment and
the only working route to the human queue. Fails closed on silence, like
every other branch here.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DCHeEto78BefsrFae2XXYH"
```

---

### Task 10: The nine-to-ten sweep

Twenty files reference the roster and eighteen lines say "nine" in so many words. Those are two different jobs. This task does the reading one.

**Files:**
- Modify: `README.md` (section 4 roster table and its opening line, section 10 tree at line 204, section 12 credentials at line 258)
- Modify: `docs/agent-contract.md:129`
- Modify: `evals/README.md:13`, `evals/README.md:35`
- Modify: `claude-agents/hooks/README.md:169`, `:376`
- Modify: `claude-agents/hooks/board-subagent-stop.sh:324` (comment), `evals/lib/board-hook-contract.sh:196` (comment)
- Modify: `claude-agents/skills/board/SKILL.md`, `claude-agents/agents/lead.md`, `claude-agents/agents/fleet-steward.md`, `docs/runs/README.md` where each names the roster

**Interfaces:**
- Consumes: everything above.
- Produces: documentation that matches the code.

- [ ] **Step 1: Add the roster row**

In `README.md` section 4, change the opening from "Nine agents, all shared through the plugin" to "Ten agents, all shared through the plugin", and add a row to the table after `reviewer`:

```
| `refuter` | Try to break a change and report what broke it: surviving mutations, tests that pass for the wrong reason, claims the evidence does not support. Never fixes | `opus` | high | Read, Grep, Glob, Bash, Write, Edit (outside the project only), rzem-memory MCP (read) | rzem-memory (read) | none | glossary, handoff, looping, using-memory, run-article |
```

- [ ] **Step 2: Do NOT touch the history**

Confirm, before editing anything else, that these are left exactly as they are:

```bash
grep -n 'nine' claude-agents/CHANGELOG.md
grep -rn 'nine' docs/runs/
sed -n '15p' README.md
```

Every line those print records what was true when it was written. A changelog entry saying v0.1.0 shipped nine agents is still correct. Changing it would be falsifying the record, and it is the single easiest mistake to make in this task.

- [ ] **Step 3: Update the present-tense claims**

Work through each remaining file and change only sentences that describe the fleet as it is now. The wording differs per site, so read each one; a blanket `sed` is what this step exists to prevent.

- [ ] **Step 4: Check nothing was missed and nothing historical moved**

Run:
```bash
git diff --stat
git diff claude-agents/CHANGELOG.md docs/runs/ | wc -l
grep -rn 'nine agents\|all nine\|nine shared' --include='*.md' --include='*.sh' --include='*.json' . | grep -v '^./.git' | grep -v CHANGELOG | grep -v 'docs/runs'
```
Expected: the second command prints `0` - no changes to history. The third prints nothing - no present-tense claim left saying nine.

- [ ] **Step 5: Run the suite and commit**

```bash
bash evals/lib/check-all.sh
git add -A
git commit -m "Ten agents, everywhere it is said in the present tense

Twenty files reference the roster and eighteen lines say nine. Those are
two jobs: the second is a replacement, the first needs reading, and this
does the reading one.

What is deliberately unchanged: every occurrence in CHANGELOG.md, under
docs/runs/, and in README's changelog sections. Those record what was true
when they were written, and a changelog entry saying v0.1.0 shipped nine
agents is still correct. Rewriting them would falsify the record, which is
the easiest mistake available in a sweep like this.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DCHeEto78BefsrFae2XXYH"
```

---

### Task 11: Version, changelog, glossary

**Files:**
- Modify: `claude-agents/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
- Modify: `claude-agents/CHANGELOG.md`
- Modify: `templates/rules/glossary.md` (generated)
- Modify: `Still open, deliberately not touched.md`

- [ ] **Step 1: Regenerate the glossary**

Run: `bash scripts/gen-glossary-rule.sh`

Expected: either "up to date" or a rewritten `templates/rules/glossary.md`.

- [ ] **Step 2: Bump the version in both places**

`0.6.0` becomes `0.7.0` - a minor bump, because this adds a role and a flag without changing what an existing caller gets.

```bash
sed -i '' 's/"version": "0.6.0"/"version": "0.7.0"/' claude-agents/.claude-plugin/plugin.json .claude-plugin/marketplace.json
grep -h '"version"' claude-agents/.claude-plugin/plugin.json
```

- [ ] **Step 3: Write the changelog entry**

Add a `## [0.7.0] - <date>` section above `## [0.6.0]`, with `### Added` covering the refuter, the `looping` skill, `roster-contract.sh` and the `refute: true` flag, and `### Changed` covering coder's three invariants, reviewer's two questions and the roster sweep. Add the compare link at the foot of the file:

```
[0.7.0]: https://github.com/rzem-ai/claude-agents/compare/v0.6.0...v0.7.0
```

and repoint `[Unreleased]` at `v0.7.0...HEAD`.

- [ ] **Step 4: Update the open-items file**

In `Still open, deliberately not touched.md`, record under the newest round:

- The refuter has never been run against a live Claude. Its evals exist and its permissions are pinned deterministically, but whether an agent given that body refutes rather than reviews is exactly what cannot be tested without a model.
- The mutation budget per round is unbounded. The spec flagged it; nothing implements it. A refuter on a large repository may run the suite many times.

- [ ] **Step 5: Verify and commit**

```bash
bash evals/lib/check-all.sh
git add -A
git commit -m "Close the round: v0.7.0, and what it still cannot prove

The refuter's permissions are pinned deterministically and its evals exist,
but whether an agent given that body actually refutes rather than reviews
is the one thing no stubbed suite can show. That goes in the open-items
file rather than in a claim.

So does the mutation budget, which the design flagged and this round does
not implement.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DCHeEto78BefsrFae2XXYH"
```

---

## Self-review

**Spec coverage.** Section 4 (the refuter) is Tasks 2, 3, 4, 5. Section 5 (coder) is Task 7. Section 6 (reviewer) is Task 8. Section 7 (the skill) is Task 6. Section 8 (review-round) is Task 9. Section 9's enforcement table is split across Tasks 2 and 9, except the mutation-evidence check, which section 9 assigns to the workflow and no task implements. **Gap, deliberate:** it depends on coder's Done-bullet wording from Task 7 being stable, and pinning a workflow check to a bullet format on the same day the bullet is invented is how format obligations decay. It goes in the open-items file at Task 11 Step 4 and gets built once there is a real handoff to parse. Section 10 is Task 10. Section 11 is Task 11 Step 4. Section 13's decisions are honoured in Tasks 9, 10 and 3 respectively.

**Placeholder scan.** Task 5 Step 1 and Task 6 Step 1 describe content rather than showing it, and both are prose files whose value is in the writing rather than in a structure that can be dictated. Each names the shape, the source to follow and what every section must cover. Task 10 Step 3 deliberately does not enumerate its edits, and says why: the wording differs per site and a blanket replacement is the failure it exists to prevent.

**Type consistency.** `REFUTER` is defined once (Task 9 Step 3) and used once. `readHandoff` and its `.blockers` and `.done` fields are existing functions in `review-round.js`, used unchanged. `check`, `deny_write`, `allow_write`, `allow_bash`, `deny_bash_saying`, `bash_event` and `$PROJECT` all exist in `scope-hook-contract.sh` before Task 2. `responder`, `handoff` and `FIX` all exist in `workflow-logic.mjs` before Task 9. `roster-contract.sh` takes no arguments and is invoked identically in Tasks 1, 3, 4, 5 and 7.
