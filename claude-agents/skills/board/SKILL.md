---
name: board
description: How the Notion board works - the two databases, the meaning of the five columns (to do, doing, blocked, blocked by human, done), which columns are written by hooks and which a human-facing assistant writes itself, how the handoff's Decisions needed lines reach the human queue, and what earns a board item at all.
when_to_use: Read before filing, reading, moving, commenting on or closing anything in the Projects or Tasks databases, before reporting board status to Alex, and whenever you are deciding whether a piece of work is board work or just a task inside the session.
---

# The board

Notion holds two databases and the board is a view on one of them. Nothing sits between the board and Claude Code's native task list.

**Projects** - one row per bounded body of work in a repo or product area. Initiative is a select field here, so a goal spanning several projects has somewhere to live.

**Tasks** - one row per tracked unit of work, related to a project, with Milestone as a field, sub-issues as a self-relation, and an Outcome field used once a row reaches done. The board is the five-column view on this database. One workspace holds everything - home lab, the fleet, rzem.guru, client work, personal admin - because a board you have to mentally join to another board is not one place to look.

## What earns an item

An issue earns a row. That is the unit of work Alex cares about, and it either has a spec or is trivial enough not to need one. A sub-issue earns a row too and stays related to its parent.

A Task in the glossary sense never appears on the board. Tasks are the execution layer inside a session, cheap and many, created with `TaskCreate` and dead when the session ends. One issue may spawn twenty of them and the board does not move. Sessions, phases, rounds, handoffs and reviews are not items either. If you are filing something to remember it for the next ten minutes, it is a task, not an item.

Work that surfaces mid-run is not filed by the agent that found it. It leaves the run as a `Propose item:` line under Decisions needed and the lead files it.

## The five columns

| Column | Means | Written by, in the fleet |
|---|---|---|
| To do | Filed, not started | Alex, or the lead filing a proposal |
| Doing | An agent has picked it up | `SubagentStart` hook |
| Blocked | Waiting on something that is not Alex - a build, an API, another item, or a run that failed or was cancelled | `SubagentStop` on status failure or cancelled, and `TaskCompleted` when tests fail |
| Blocked by human | Waiting on an answer from Alex. The human queue | `SubagentStop`, on a `Blocker:` line in the handoff |
| Done | The run finished and its tests passed | `TaskCompleted` hook |

Blocked and blocked by human are separate columns because they need different responses. Blocked is something to wait out or work around. Blocked by human costs Alex an interruption, and it is the only column he monitors.

## Who writes the columns

Two environments share this board and they write it differently. Know which one you are in before you touch anything.

**In the fleet, columns are written by hooks and never by an agent.** Three hooks cover every transition in the table above, each PATCHing the Notion API directly. So do not move an item, do not ask for one to be moved, and do not report that you moved one. The only thing you contribute is a correctly formatted handoff, because that is what the hook reads. An agent body or a run that tries to update a status is wrong even when the status it wants is correct.

**In Cowork there are no hooks, so the assistant layer writes the board by instruction.** Angus moves items himself, and the discipline the hooks provide has to come from three rules instead. First, move an item to doing when you actually start it and to done when it is finished and verified, in the turn it happens, never batched up at the end of a day. Second, the only thing that goes into blocked by human is something genuinely waiting on Alex, with the reason as a comment on the row. Third, never file an item for a step you are about to take in the same turn - that is a task.

## Decisions needed and the human queue

Every handoff ends with a Decisions needed heading carrying typed lines, and only one of the three types touches the board.

`Blocker:` moves the item into blocked by human and the blocker text lands as a comment on the row, so the queue answers what is blocked, on what, and for how long, without anyone opening a transcript. `Propose item:` becomes a new row in to do, filed by the lead. `Propose memory:` never touches the board at all - it is corpus work for the researcher or the lead.

A false blocker is not free. The queue is read out to Alex at 8am and 4pm Sydney time, and anything sitting in it for more than four hours between 8am and 6pm escalates immediately. Park a routine suggestion there and you have interrupted him for nothing; miss a real one and he never learns he was needed.

## Done, and the outcome field

There is no success column. Done means the run finished and its tests passed, and nothing more. Whether the work was any good is the Outcome field on the row - shipped, abandoned or superseded - set when the answer is known, which is usually later and often by Alex.

So an item that turns out to have been the wrong idea is done with an outcome of abandoned, not dragged back into to do. Replacement work is a new item, and the old row is superseded. A second terminal column is exactly where items go to be stranded, which is why there is not one.

## Item conventions

Title the row as the change, in the imperative, in the glossary's words - "Rotate refresh tokens on reuse", not "refresh token stuff" and not "Investigate the auth epic". One item, one outcome. If a row needs two answers to close, it is two rows or a parent with sub-issues.

Every item is related to a project, because an item with no project is invisible in every view that matters. Milestone is set only when there is a real date or deliverable, not to express urgency.

Link `docs/specs/<issue>.md` and `docs/plans/<issue>.md` on the row rather than pasting their contents into it. The repo is the source of truth for both and a copy on the row goes stale silently.

Add comments, do not rewrite fields. The history of a row is how a blocked item is understood a week later, and an edited description destroys it. Never delete a row - abandon it.
