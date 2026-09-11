---
description: Preflight the fleet in this project - plugin, agents, settings, skeleton - then take the first idea and start the spec pipeline on it
argument-hint: [the idea, in a sentence or a brain dump]
---

Kick off fleet work in this project. Run the preflight first, and start work only if it comes back green. This command is what `/claude-agents:init` points at after its restart, so assume nothing - the point of the preflight is to catch a half-finished setup.

## Preflight

Check each of these, collecting results rather than stopping at the first failure:

1. **Plugin.** The claude-agents agents are available (`scout`, `spec-writer`, `coder`, `reviewer`, `refuter`, `ui-designer`, `tech-writer`, `researcher`, `fleet-steward` and `lead` appear as `claude-agents:` agent types). If they are missing, the plugin is not installed or the marketplace cache is stale.
2. **Lead.** `.claude/settings.json` exists and sets `agent` to `claude-agents:lead`. Note, without failing, if the current session is visibly not running as the lead - that means the settings changed since the session started and a restart is needed.
3. **Skeleton.** `CLAUDE.md` exists at the project root and contains no `<FILL: ...>` markers. A marker left in place is a line the session reads literally on every turn, so surviving markers are a failure, not a note.
4. **Glossary rule.** `.claude/rules/glossary.md` exists.
5. **Work directories.** `docs/specs/` and `docs/plans/` exist.
6. **Board, only if configured.** If the session carries `CLAUDE_AGENTS_BOARD_PAGE_ID` or the project documents a Notion board, confirm the Notion tools respond. No board configured is fine and is not a failure.

If anything failed: report every failure with its one-line fix (`/claude-agents:init` for missing skeleton pieces, restart-and-trust for a plugin or agent problem, edit the marker for a surviving `<FILL: ...>`), and stop. Do not start work on a red preflight.

## The idea

The text after the command is the idea. If there is none, ask the human one open question - what are we building, in a sentence or a brain dump, messy is fine - and wait. Do not invent a task, and do not substitute a repo TODO for an answer.

## Start

With a green preflight and an idea in hand, start the fleet's intake as the lead's routing says: an unshaped idea goes to `spec-writer`, whose interview opens the problem out before the spec closes it down - the `spec-to-plan` flow. Recall from the memory server and send `scout` ahead if the idea touches existing code, then spawn `spec-writer` with the idea verbatim, not paraphrased. From there the normal pipeline holds: the human edits the spec, the plan is written and approved, and only then does a `coder` run.

Report the preflight result either way - one line per check when green, the failure list when not.
