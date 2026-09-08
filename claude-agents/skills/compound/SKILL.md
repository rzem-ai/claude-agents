---
name: compound
description: Capture what a finished unit of work taught you into the one place it will be read again - a project convention into .claude/rules/, a repeatable procedure into a skill, a durable decision into the shared memory corpus as a proposed line in the handoff - and throw away everything that fails the three tests. The discipline is mostly in what you decline to keep.
when_to_use: Run once at the end of a unit of work that is finished and verified - a merged plan phase, a closed review round, a debugging session that ended in a fix, an approved spec. Also use when Alex says capture the learnings, write this back, or compound. Never run it mid-task or on work that has not landed.
---

# Compound

At the end of a unit of work, some of what you learned is worth more than the work. This is the step that moves it somewhere it will be read again, and throws away the rest. Both halves matter - a rules directory nobody trusts is worse than an empty one, because it costs context on every matching turn and buys nothing.

## When to run

Run once, on a unit of work that is finished and verified. A merged plan phase, a review round that closed, a debugging session that ended in a fix, a spec Alex approved.

Do not run it mid-work, do not run it per turn, and do not run it just because a session is ending. Work that failed or was cancelled produces no learnings, only guesses, and an unverified run is the worst possible source for a rule that will be believed by everything that comes after it.

## What is worth keeping

Three tests, all three or it is not a learning.

**It surprised you.** You got it wrong first, or you had to go and find out. Something you already knew before the task started is not a learning.

**It will recur.** You can name the next situation where it applies. If the only place it is true is the file you just edited, the code says it better than a rule can.

**It is durable.** It will still be true next month. Anything tied to a branch, a ticket, a version you are about to upgrade or a person's current opinion goes stale faster than anyone will notice it has.

Most units of work produce zero or one learning. Three is the ceiling for a single run, and hitting it repeatedly means the tests are being applied too generously.

Never keep a restatement of the task, a summary of what you did, a fact the code or a type already states, or anything the glossary, CLAUDE.md or an existing rule already says.

## Where each kind goes

| Kind of learning | Home | Note |
|---|---|---|
| A convention this project follows | `.claude/rules/<topic>.md` | Add a `paths:` glob if it only applies to some files. A rule without one loads on every turn, so earn it |
| A fact that must be true on every turn and fits in a sentence | `CLAUDE.md` | Under 200 lines, facts only, never a procedure |
| A repeatable procedure, multi-step, worth following again | a skill under `claude-agents/skills/` | Edit an existing skill before you add a new one |
| A durable decision about the work, and why | the shared rzem-memory corpus | Only `researcher` and the lead can write there. Everyone else writes a `Propose memory:` line and one of them files it |
| Work you noticed but did not do | a board item | A `Propose item:` line under Decisions needed. The lead files it. Never a rule |

The commonest mistake is filing a procedure as a rule. If it has steps, it is a skill. If it is one sentence a reader either obeys or does not, it is a rule.

The second commonest is writing a memory that is really a rule. Memory answers "what did we decide about this last time" across projects and sessions. A rule shapes what happens in this repo without anyone asking. When both fit, prefer the rule, because it applies itself.

## The discipline

Search before you write. Every new file competes with the ones already there, and two rules that half agree are worse than one that is out of date, because a reader has to decide which is live.

Edit before you add. Updating an existing rule or skill is almost always the right move, and a new file needs a reason you would defend.

Delete on contradiction. When a learning contradicts something already written down, change the old text. Never leave both and never soften the old one into something that no longer says anything.

Every addition carries one line of provenance - the date and the unit of work it came from - so anything unreferenced can be found and pruned later without archaeology. The steward re-reads `.claude/rules/` quarterly and deletes what has not earned its place.

Nothing here writes to the board, and nothing here is a substitute for the handoff. If a learning is important enough to act on now, it is a line under Decisions needed, not a file somebody might read.

## How you work

1. Name the unit of work in one sentence and confirm it landed and was verified. If it did not, stop.
2. List the candidate learnings, plainly, before judging any of them.
3. Apply the three tests to each and discard everything that fails. Say what you discarded, so the discarding is visible rather than invisible.
4. For each survivor, search `.claude/rules/`, the skills directory and rzem-memory for where it already lives.
5. Edit or add one file per learning, with its provenance line. Keep it as short as the thing allows.
6. Record it in the handoff - what you wrote goes under Done, a corpus entry you cannot write yourself is a `Propose memory:` line, and new work you noticed is a `Propose item:` line.
