# Making four readers of the handoff format agree

2026-09-08, coder, handoff-format-divergence. Closed the gap that let a `- Blocker:` line under `## Done` pass validation and then be silently discarded, and added the parity harness that keeps the production validator and the CI gate identical over 28 fixture cases.

## What the run was

Four things read the handoff. `claude-agents/skills/handoff/SKILL.md` states the format for agents. `claude-agents/hooks/board-subagent-stop.sh` validates it on every successful run and exits 2 to send a bad one back. `evals/lib/handoff-check.sh` applies the same rules in CI. And `extract_blockers`, an awk one-liner inside the stop hook, pulls the `Blocker:` lines that move a board item into the human queue.

The fourth was the one nobody counted. It is scoped to the `## Decisions needed` section, which is correct, but the validator did not reject a typed line found anywhere else. So a handoff with `- Blocker: The refresh token lifetime is unspecified` under `## Done` parsed clean, the extractor looked only under Decisions needed, found nothing, and the run finished green. The item stayed where it was, no comment was posted about it, and Alex never learned he was needed. `evals/fixtures/handoff-cases/bad-blocker-under-done.txt` is that message, pinned.

## What was tried and abandoned

**Widen the extractor to grep the whole message for `^- Blocker: `.** The obvious fix, and wrong twice over. It rescues the line silently, so an agent that has the format wrong is never told, and the next handoff has the same defect. It also lifts blockers out of prose: preamble above the handoff is deliberately unparsed, the lead's own eval quotes a typed line while explaining what it did with someone else's handoff, and two fixtures now hold that behaviour still (`valid-token-named-in-prose`, `valid-typed-line-quoted-in-preamble`). Grepping the message would have parked those quotations in the human queue.

**Move the line for the agent, from Done into Decisions needed.** Same silent rescue, plus it makes a board hook a writer of handoffs. The hook would then be repairing a contract it also enforces, and the first time the repair guessed wrong there would be nothing in the log to show it had happened.

**Say it harder in the skill and leave the machinery alone.** Rejected on the argument the whole board design rests on: prose in a preloaded skill decays, and a rule that only holds while nine agents remember it is not a rule. The skill did get a paragraph, but as an explanation of the check rather than in place of it.

**One shared validator sourced by both the hook and the CI gate.** The tempting structural answer, and it does not survive installation. The plugin ships as `claude-agents/` alone; a machine that installs it has no `evals/` tree, so a hook that sources a file from there breaks on exactly the machines the hook is for. Inverting it and making CI source the hook was no better, since CI reads a file and the hook reads hook JSON on stdin.

## What the constraint turned out to be

The two implementations cannot be one file, so identity has to be proved rather than assumed. That is what `evals/lib/handoff-parity.sh` is: it runs the real stop hook, with `CLAUDE_AGENTS_BOARD=off` and a throwaway config directory, and the CI gate over every case in `evals/fixtures/handoff-cases/`, and fails if a verdict differs from the other side or from `expected.tsv`. Twenty-eight cases, eight valid and twenty invalid. The rule set stayed in two places; only the agreement is mechanical.

The surprise was how much of the format is tolerance rather than rules. Preamble prose, CRLF endings, a missing trailing newline, trailing blank lines, a typed token named mid-sentence: five of the eight valid cases exist to stop a future tightening from breaking something that was always legal. The invalid cases were easy to write. The valid ones were the work.

## What to do differently

Count the readers of a format before changing it, and write them down. Three were files anyone would have listed; the fourth was six lines of awk inside a hook, and it was the one with the bug.

Write the fixture set before the fix. Most of the cases here were written afterwards, from the code, which is the wrong direction: a case derived from the implementation agrees with the implementation by construction.

Next person: run `evals/lib/handoff-parity.sh` after touching either side, and `-v` prints each side's reasons when a verdict is not what you expected. Wording differs between the two on purpose; the verdict is the contract.
