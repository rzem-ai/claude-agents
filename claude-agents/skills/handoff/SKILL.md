---
name: handoff
description: The handoff format every fleet subagent ends its final message with - the four fixed headings Done, Not done, Unverified and Decisions needed, and the typed Blocker / Propose item / Propose memory lines that the SubagentStop hook parses. Preloaded into every agent; not discovered.
disable-model-invocation: true
---

# Handoff format

End every final message with a handoff. It is a machine contract, not a style guide: a `SubagentStop` hook greps `last_assistant_message` for it. Deviate and either a blocker is missed, so Alex never learns he is needed, or a routine suggestion parks a false alarm in his queue.

## Structure

Four sections. Always these four, always this order, always all four present:

```
## Done
## Not done
## Unverified
## Decisions needed
```

Rules a `grep`/`sed` parser depends on:

- Heading lines are exactly `## ` plus the wording above. Level 2, one space, that capitalisation, no trailing punctuation, no numbering, no bold. Anchor: `^## (Done|Not done|Unverified|Decisions needed)$`.
- Use no other level-2 heading anywhere in the final message.
- Every item is one markdown list item starting `- ` at column 0. No nesting, no sub-bullets, no blank lines inside a section, no code fences, no tables.
- One item is one line. Items never wrap - the newline ends the item. Keep each under roughly 200 characters; split a long one into two items.
- An empty section contains exactly one line: `- None`. Never omit a section and never leave one blank, so a parser never has to distinguish "no blockers" from "the agent forgot the section".
- The handoff is the last thing in the message. Nothing follows the last item of Decisions needed.

## What goes where

- **Done** - what you changed or established, with paths. Verified work only.
- **Not done** - in-scope work you did not finish, including anything stopped by a failure or a cancellation.
- **Unverified** - claims you could not prove: untested code, commands you did not run, assumptions you carried forward.
- **Decisions needed** - typed lines only, per below.

## Typed lines

Every line under Decisions needed carries one of exactly three prefixes. Case-sensitive, spelled exactly as written, colon then a single space:

- `- Blocker: ` - the work is stopped until Alex answers. This and only this moves the board item into "blocked by human". Use it only when you genuinely cannot proceed; it costs him an interruption.
- `- Propose item: ` - suggested new board work. The lead files it. It never touches the human queue.
- `- Propose memory: ` - worth filing into the shared rzem-memory corpus. Only `researcher` and the lead can write there, so one of them actions it.

Anchor: `^- (Blocker|Propose item|Propose memory): `.

There is no fourth prefix and an untyped line is invalid. Never write the token `Blocker:` anywhere else in the message - not in prose, quotes, examples or file contents - because the hook greps the whole message. If you must name it, drop the colon.

## Do not signal status in the text

`SubagentStop` receives a `status` field of `success`, `failure` or `cancelled` from the harness, independently of anything you write. Do not try to signal failure through the handoff: no status line, no "FAILED", no truncated message. A run that failed still emits all four sections, and what went wrong goes under Not done.

## Example

```
## Done
- Added POST /sessions/refresh in src/api/auth.ts with rotation on reuse.
- Rotation unit tests pass: pnpm test src/api/auth.test.ts.

## Not done
- Rate limiting on the endpoint. Phase 3 of the plan, not started.

## Unverified
- Never exercised against staging Redis, only the in-memory fake.
- Assumed refresh tokens are single-use; the spec does not say.

## Decisions needed
- Blocker: Refresh token TTL is unspecified and phase 3 depends on it. 7 days or 30?
- Propose item: Migrate the legacy /token endpoint onto the same rotation logic.
- Propose memory: We chose rotation-on-reuse over sliding expiry for rzem services.
```
