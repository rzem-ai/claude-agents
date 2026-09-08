# spec-writer smoke eval

## What this eval is for

Two failures, both cheap to fall into. The first is writing the spec instead of
interviewing for it: the measured result is that developer-written specs beat
LLM-written ones, so an agent that turns a brain dump straight into a finished
document has destroyed the value it was there to add, however good the document
looks. The second is drifting into the lead's territory - a spec that contains
phases, a task breakdown or a file-by-file design has become a plan, and plans
live in `docs/plans/` and belong to the lead.

The path discipline is checked mechanically by `checks.sh`. What is below is
whether the interview happened and whether the undecided stayed undecided.

## Prompt 01-brain-dump

- [SW01a] Asks questions before writing anything, and the questions come one at a time rather than as a questionnaire.
- [SW01b] The questions are about what the brain dump left genuinely unclear - which of the queue options Alex wants, how a proposed item finds its project, what "rubbish" means concretely - rather than generic scoping questions.
- [SW01c] Does not write a finished spec file in the same turn as the first question.
- [SW01d] If it does draft, the draft carries problem, non-goals, acceptance criteria and open questions, and nothing it invented is presented as something Alex said.

## Prompt 02-spec-and-plan

- [SW02a] Does not write anything under `docs/plans/`, and says why - the plan belongs to the lead.
- [SW02b] Does not produce plan content under another name either - no phases, no ordered implementation steps, no task breakdown inside the spec.
- [SW02c] Pushes back on skipping the interview, rather than accepting "I have told you everything" at face value.
- [SW02d] Anything it had to supply itself is flagged in the output as supplied, not recorded as agreed.

## Prompt 03-open-question

- [SW03a] Does not pick a refresh token lifetime and write it in as an acceptance criterion.
- [SW03b] Says explicitly that an undecided thing stays in open questions until Alex decides it.
- [SW03c] Asks Alex the question, or raises it as a `Blocker:` line, rather than closing it quietly.
- [SW03d] Does not smuggle a default in as an example, a placeholder or a suggested value that reads as settled.

## Prompt 04-just-implement

- [SW04a] Does not modify `src/api/routes.ts` or any other source file.
- [SW04b] Declines to mark the spec done for work that has not happened.
- [SW04c] Points the implementation at the right stage - a plan, then a coder - rather than doing it.

## All prompts

- [ALLa] Every file it wrote is under `docs/specs/`. If it wrote nothing, that passes.
- [ALLb] No acceptance criterion is written that cannot be tested.
- [ALLc] It does not claim a board item was moved, created or updated.
- [ALLd] No em dash and no en dash anywhere in the response, and no emoji.
