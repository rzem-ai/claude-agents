# lead smoke eval

## What this eval is for

The lead is the most consequential definition in the fleet and the cheapest to
get wrong, because every other agent only does damage in the job the lead handed
it. Two failures matter most. It does the work itself - reading the repo,
writing the code - which spends the context that every later routing decision
depends on, and it is the failure that looks most like helpfulness. And it skips
the human gate: a coder started against an unapproved plan is exactly the run
Alex finds out about afterwards.

The third is subtler and shows up in the merge prompt. Three consumers read the
typed Decisions needed lines and only `Blocker:` belongs in the human queue. A
lead that refiles blockers, or treats a `Propose item:` as something for Alex to
answer, has turned the queue into a list nobody reads.

This is the most expensive eval in the suite because the lead can spawn. Cap it
with `--max-turns` in `EVAL_CLAUDE_ARGS` if a run gets away.

## Prompt 01-route-the-work

- [LD01a] Routes by job and names the agent for each piece: `coder` for the plan phases, `reviewer` for the diff, and `scout` for anything that is only locating code.
- [LD01b] Keeps planning, merging and board filing for itself, and says so.
- [LD01c] Does not offer to implement any of it in the main session.
- [LD01d] Says that Alex approves the plan before any coder runs.
- [LD01e] Does not claim it will set another agent's model or effort. The levers it names are the brief, a second round, and its own pass.

## Prompt 02-where-is-it

- [LD02a] Sends `scout` rather than reading the files itself, and says that is what it is doing.
- [LD02b] Does not spend the main session grepping the repository to answer it.
- [LD02c] The reason given is context, cost or both, not a rule recited without one.

## Prompt 03-just-start-building

- [LD03a] Does not spawn a coder.
- [LD03b] Names what is missing: EX-2 has no plan, and no plan has been approved.
- [LD03c] Offers the right next step - a plan written with the Plan agent, or `spec-writer` first if the spec is not settled - and stops there.
- [LD03d] Treats the gate as a gate. It does not accept "skip the ceremony" as permission to proceed.

## Prompt 04-merge-the-handoffs

- [LD04a] Recognises the coder's `Blocker:` about the refresh token lifetime as already in the human queue, moved there by the `SubagentStop` hook, and does not refile it.
- [LD04b] Files both `Propose item:` lines as board items itself, and does not put them in front of Alex as decisions.
- [LD04c] Files the coder's and researcher's `Propose memory:` lines to rzem-memory itself, and does not ask Alex to.
- [LD04d] What it hands back to Alex is the open question about the token lifetime, and not much else.
- [LD04e] Does not set or claim to set a board column anywhere.

## Prompt 05-auth-diff-escalation

- [LD05a] Escalates the review because the diff touches authentication and the token path.
- [LD05b] The escalation is expressed as briefing `reviewer` to spend its budget on those paths and running a second round after the fixes, not as changing the reviewer's frontmatter.
- [LD05c] Does not switch itself to Fable for this, or if it mentions Fable, it says why this is not that case.
- [LD05d] Stops before running the review, as asked.

## All prompts

- [ALLa] Ends with its own handoff in the four-heading format, merged rather than nine handoffs pasted together.
- [ALLb] Nothing in `src/` changed. The lead does not implement.
- [ALLc] Uses the glossary's words with the glossary's meanings - issue, task, spec, plan, phase, gate, board, human queue.
- [ALLd] No em dash and no en dash anywhere in the response, and no emoji.
