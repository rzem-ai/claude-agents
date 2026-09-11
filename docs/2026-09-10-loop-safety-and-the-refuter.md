# Loop safety, and the refuter

Author: Angus, for Alex. Date: 10 September 2026. Status: design, for approval before a plan is written.

## 1. What this is for

The fleet can already be told to work until something is done. Nothing in it makes that safe. This design adds the missing half: a tenth agent whose job is to try to break the work, a definition of "done" that does not depend on the agent doing the work, and bounds that live where the working agent cannot reach them.

It is written from one night of evidence rather than from first principles, and section 2 is that evidence. Where a decision rests on something that has not been observed, section 11 says so.

## 2. The evidence

On 9 and 10 September a single unattended session fixed two reported defects and, in the course of it, introduced five more. Every one of the five was caught by an agent told to refute, not by the agent that wrote them, and not by the deterministic suite.

| What went wrong | Why the author could not catch it |
|---|---|
| Five regressions, including a hook that silently retired `ui-designer`'s entire install ban | The author is the worst-placed judge of their own blind spot |
| Three of the author's new tests watched nothing; adversarial review found sixteen more | A green suite looks identical whether or not it tests anything |
| `maxRounds: "three"` disabled the cap and the loop ran until the process died | A bound the running agent controls is not a bound |
| Scope grew from two items to eleven with no terminator | "Done" defined by the doer means "when I feel finished" |
| A commit message stated an inference as fact | Drift is invisible from inside |

Two further observations shaped the design. First, the agents that found things were told to **refute** - "assume it is wrong, find the proof, a review that finds nothing has not looked hard enough" - and the ones told to review returned politeness. That is a difference of instruction, not of difficulty. Second, the single highest-yield question of the night was "would this test fail if the fix were reverted", and no agent in the fleet asks it.

## 3. The principle

**Done is defined by failure to refute, not by the doer's satisfaction.**

A round cap is arbitrary and the working agent's judgement is the least reliable input available. The stopping condition that actually held was: an independent agent tried to break the work and the only thing it could find was an equivalent mutant that no test could ever kill.

Everything below serves that sentence.

## 4. The refuter

### 4.1 Why it cannot be an existing agent

`reviewer` is the obvious home and it will not work. Its defining invariant is "never run tests, builds or installs; if something needs running, that is a finding, not a task", and `enforce-agent-scope.sh` holds it to that: `cp`, `node`, `bash` and `python3` are all denied. Mutation testing is copying a file, changing it, and running the suite. A reviewer that could do that would no longer be a reviewer, and the invariant it would lose is the one that makes a reviewer worth having.

`coder` has the permissions and the wrong incentives: an agent that can fix what it finds will fix what it finds, and then the finding is gone and so is the evidence.

The refuter needs coder-shaped execution with reviewer-shaped intent. No current role has that pair.

### 4.2 Frontmatter

Per `docs/agent-contract.md` section 1.

```
name: refuter
description: Tries to break a change and reports what broke it. Runs mutation tests, never fixes. Use after a coder finishes and a reviewer has read the diff, and before a loop is called done.
model: opus
effort: high
tools: Read, Grep, Glob, Bash, Write, Edit,
  mcp__claude_ai_Memory__memory_search, mcp__claude_ai_Memory__memory_read_document,
  mcp__claude_ai_Memory__memory_tree, mcp__claude_ai_Memory__memory_kv_get,
  mcp__claude_ai_Memory__memory_kv_list
disallowedTools: NotebookEdit, mcp__claude_ai_Memory__memory_capture,
  mcp__claude_ai_Memory__memory_forget, mcp__claude_ai_Memory__memory_kv_set,
  mcp__claude_ai_Memory__memory_kv_delete
color: red
skills: glossary, handoff, using-memory, looping, run-article
```

The colour is a collision and there is no way around it: the palette has eight values and this makes ten agents, with `cyan` already doubled between `scout` and `fleet-steward`. `red`, shared with `reviewer`, is the human's decision and the right one - the two roles sit next to each other in the pipeline and both report on work without touching it, so a reader seeing red learns something true either way.

`model: opus` and `effort: high` because this is judgement work and the night's evidence came from opus-class agents. `memory` and `isolation` are omitted: it writes nothing in the project, so there is nothing to isolate.

It holds `Write` and `Edit` deliberately, which no other read-only role does. Section 4.3 is what makes that safe.

### 4.3 Permissions

Three rules, enforced in two places.

**No writes inside the project.** This is the inverse of every existing write scope. `check-write-scope.py` is an allowlist model - a target outside every allowed root is denied - so the refuter cannot be expressed by adding a row to `default_scope`. It needs its own branch:

```python
if role == 'refuter':
    return 1 if inside(target, project) else 0
```

Physically resolved, like the others, so a symlink pointing back into the project resolves back into it. What bounds "outside the project" is the sandbox's own `denyWrite` in `home/settings.json`, which already covers `~/.ssh`, `~/.aws`, `.env` and the rest. That is the correct division: this layer expresses the role boundary, the sandbox expresses the credential boundary.

**May execute.** No Bash command allowlist. Running the suite, `node`, `bash` and `python3` is the job, and an allowlist would have to be so wide it would express nothing.

**Read-only git.** The same verb list `reviewer` uses. It copies and mutates a scratch tree; it never commits, and it never moves a ref in the real repository.

The `enforce_refuter` branch in `enforce-agent-scope.sh` carries the git verb check. The write rule goes through the existing `check-write-scope.py` dispatch, with `refuter` added to `ROLES`.

### 4.4 Body

Four H2 sections in the contract's order, under 60 lines.

The invariants, which are the load-bearing part:

```
Never write inside the project. Your scratch tree lives outside it.
Never fix what you find. A refutation is a finding with a reproduction, not a patch.
Never report a mutation as surviving without confirming the process exited cleanly.
Never say you could not break something you did not try to break.
```

The third is not general caution. On the night this design comes from, a mutation that crashed the test process produced no failure lines and was recorded as surviving - which inverted the finding, because a mutant that kills the process is the strongest in the set, not the weakest. Any mutation harness must treat a non-zero exit as a kill and must assert the baseline is green before each mutant.

The fourth is the difference between a refuter and a reviewer, written down.

### 4.5 What it returns

A handoff in the ordinary format. No new heading, no fourth typed prefix. The mapping:

- **Done** - what it tried, what survived, what died. Each surviving mutant is a finding with the exact edit that produced it.
- **Not done** - axes it could not attack, and why.
- **Unverified** - anything it suspects but could not reproduce.
- **Decisions needed** - a surviving mutant that changes behaviour is a `Blocker:` line. A test that passes for the wrong reason is a `Propose item:` line.

## 5. Changes to `coder`

Three invariant lines, plus `looping` added to its `skills` list. Nothing else, because the body is at its budget and the procedure belongs in a skill.

```
Never mark a test passing that you have not watched fail, and say in Done what makes it fail.
Never widen the phase. Work you find outside it is a Propose item: line.
Never extend your own budget. Running out is a result to report.
```

The first is `test-driven-development`'s watch-it-fail step turned into something reportable. The skill already says to do it; nothing makes it visible, and on the night this design comes from, three tests written under that skill turned out to watch nothing.

## 6. Changes to `reviewer`

Two additions to `## How you work`, no change to its invariants or its scope.

1. Ask whether the tests in the diff would fail if the fix were reverted, and raise a test that would not as a finding. The reviewer cannot run the mutation - that is the refuter's job - but it can read a test and say whether it appears to depend on the change, and it is cheaper to catch there.
2. On a numbered round after the first, give an opinion on convergence: whether this round's findings are substantially the previous round's. The reviewer holds both, and the coder is the worst-placed party to judge it.

## 7. The `looping` skill

Preloaded into `coder` and `refuter`, and only reached on loop work, so it costs nothing on an ordinary phase.

It carries the procedure the invariants imply:

- Record the baseline before the first change: the suite's result and its per-suite counts. Compare differentially at the end. `coder.md` currently says to run the tests before finishing, which catches a broken build and not a regression.
- For each new test, name the change to the fix that makes it fail. A test with no such change is decoration.
- Convergence: if this round's findings are substantially the previous round's, say so rather than starting another round.
- What the handoff should carry: baseline against now, mutations verified, budget consumed, convergence signal. As ordinary Done bullets.

## 8. Changes to `review-round`

Three, all in the existing shape.

**A refuter stage, after the verdict.** It is mandatory under `fix: true` and available on an ordinary single-round review through `refute: true`, which defaults off so that nothing running today gets slower or more expensive without being asked.

Making it reachable outside a loop is deliberate and is the cheapest way to learn whether the role works at all: a refuter pointed at an ordinary review costs one agent and produces real evidence about its behaviour, where a refuter first exercised inside a loop is being trusted with compounding errors on its first outing. Expect the opt-in form to be how it earns its place before anything depends on it.

Under `fix: true`, a round is not clean because the reviewer found nothing blocking. It is clean because the reviewer found nothing blocking **and** the refuter failed to break it. The stage carries a schema, like the other lanes, and its verdict gates the round.

**The gate fails closed.** A refuter that returns nothing stops the run with its own reason, in the same register as every other branch there. The alternative is an advisory refutation, which makes the safety mechanism optional exactly when things are going badly.

**Mutation evidence is checked, not trusted.** The workflow already receives coder's handoff as a plain string and already parses it. It refuses a round whose handoff claims new tests without naming what makes them fail.

## 9. Where enforcement lives, and where it deliberately does not

The ladder is instruction, then detection, then prevention. The fleet is thick with instructions, thin on prevention, and an instruction phrased as "the agent must remember to" decays.

| Rule | Enforced by | Why there |
|---|---|---|
| Iteration budget | the workflow | The bound must not be visible to the agent it bounds |
| No writes in the project | `check-write-scope.py` | It is a path question and that file already answers path questions |
| Read-only git | `enforce-agent-scope.sh` | Where every other role's git verbs are decided |
| Mutation evidence present | the workflow | It reads the handoff already |
| Mutation evidence correct | the refuter | Nothing mechanical can judge it |

Deliberately not enforced at hook level: the content of a handoff. Requiring new bullets would be a format obligation, and the claude-agents repo has already refused a fifth heading on the grounds that a field agents must remember is a field that decays. The workflow checking a string it already holds costs nothing and decays into a workflow failure rather than a silent one.

## 10. The nine-to-ten sweep

Twenty files reference the roster, and eighteen lines say "nine" in so many words. Those are two different jobs: the second is a find-and-replace, the first needs reading. The files, so the plan enumerates rather than discovers:

`README.md`, `docs/agent-contract.md`, `docs/runs/README.md`, `evals/README.md`, `evals/run.sh`, `scripts/install-home.sh`, `claude-agents/agents/lead.md`, `claude-agents/agents/fleet-steward.md`, `claude-agents/skills/board/SKILL.md`, `claude-agents/hooks/hooks.json` (the `SubagentStop` matcher), `claude-agents/hooks/README.md`, `claude-agents/hooks/enforce-agent-scope.sh`, `evals/lib/scope-hook-contract.sh`, and the glossary regeneration through `scripts/gen-glossary-rule.sh`.

New: `claude-agents/agents/refuter.md`, `claude-agents/skills/looping/SKILL.md`, `evals/refuter/` with `rubric.md`, `baseline.json`, `checks.sh` and `prompts/`.

This is the `fleet-steward`'s kind of sweep and it is not going to it: the human's decision is that this round does it by hand. That is the right call for two reasons. The steward's editing scope excludes several of these files, so handing it the job would mean widening that scope to do it - reopening a question deliberately left open last week. And a roster change is exactly the kind of edit where the twenty files are not twenty find-and-replaces: eighteen lines say "nine" and can be replaced, and the rest have to be read.

## 11. What this rests on that has not been observed

Stated plainly, because the previous round's lesson was that an unmeasured assumption looks exactly like a measured one.

- **Worktree isolation for a workflow-spawned agent has never been seen to work.** It bears on the refuter only lightly - the refuter writes outside the project by design and needs no worktree - but it bears heavily on `coder`, and a loop whose fixes land in the main checkout is stopped rather than adopted. That is the right failure and it means loop work may simply not run until isolation is settled.
- **Nothing here has been run against a live Claude.** Every mechanism below the workflow is testable deterministically and will be. What is not testable that way: whether an agent given the refuter's body actually refutes rather than reviews. That is what `evals/refuter/` is for, and its rubric should probe exactly that - a prompt containing a defect the agent is expected to find, and a prompt containing none, where the failure is claiming to have found one.
- **The refuter's cost is unknown.** It runs the suite repeatedly, once per mutant. On the claude-agents repo that is seconds; on a large one it may not be. The plan should include a bound on mutants per round, and the workflow should report what it dropped rather than silently sampling.

## 12. Out of scope

Not in this round: a general mutation-testing tool. The refuter mutates by hand, with judgement about which mutations are meaningful, and the night's evidence is that judgement was the valuable part - three of the mutations that mattered were ones a generic tool would not have generated, and one that a generic tool would have generated was an equivalent mutant no test can kill.

Not in this round: extending the refuter to anything but loop work. It is expensive and its value is highest where errors compound.

Not in this round: changing `reviewer`'s invariants or `coder`'s permissions.

## 13. Decisions taken

Recorded here rather than left implicit, because each one changed the shape of the plan.

1. **This round does the nine-to-ten sweep by hand**, rather than commissioning the `fleet-steward`. Section 10.
2. **The refuter runs outside loops too**, opt-in through `refute: true`, mandatory under `fix: true`. Section 8.
3. **The refuter is `red`**, shared with `reviewer`. Section 4.2.

Alex, 10 September 2026.
