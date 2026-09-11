---
description: Preflight the fleet in this project - plugin, agents, settings, skeleton - check or set up the Notion board, then take the first idea and start the spec pipeline on it
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
6. **Board.** The full check-and-setup is its own step below; here just note whether the Notion tools are available at all. No Notion connector means no board, which is fine and is not a failure.

If anything failed: report every failure with its one-line fix (`/claude-agents:init` for missing skeleton pieces, restart-and-trust for a plugin or agent problem, edit the marker for a surviving `<FILL: ...>`), and stop. Do not start work on a red preflight.

## Board

Run this step only when the Notion tools are available. Read the `board` skill first; it is the contract this step is verifying. No board is a legitimate outcome throughout - most work is not board work, and the human declining any part of this is a note in the report, never a failure.

**Check.** Search Notion for the two databases the board skill describes, **Projects** and **Tasks**. If both exist, verify the Tasks schema: a Status property whose options carry the five names the hooks expect by default - `To do`, `Doing`, `Blocked`, `Blocked by human`, `Done` - plus a relation to Projects, a Milestone field, a sub-issue self-relation and an Outcome field. Report drift precisely: a misspelled option's fix is renaming it in Notion or overriding `BOARD_COL_*` in `~/.config/claude-agents/board.env`, and the two fixes are not equivalent - the override leaves every other tool seeing the odd name.

**Setup.** If either database is missing, say what would be created and ask the human before creating anything - these are writes to their workspace. On a yes: create Projects, then Tasks with the schema above and a board view grouped by Status. Create Status as a `select` property, not `status`: the Notion API cannot create options on a `status` property, and the hooks already try both types and pin the one that works. If the human prefers a `status` property, create the databases without it and hand them the five option names to add by hand.

**What this step cannot do, said out loud.** The hooks authenticate with their own integration token at `~/.config/claude-agents/notion.token`, which every agent is denied by design - so this step can never test that token, and a board green here can still fail in the hooks. End the board section of the report with the two manual checks: the databases are shared with the hooks' Notion integration, and the token file exists at that path with mode 600 (rendered by `scripts/install-home.sh`). A `no board item` or HTTP-error line in `~/.local/state/claude-agents/log/hooks.log` after the first real spawn is the symptom of either one missing.

## The idea

The text after the command is the idea. If there is none, ask the human one open question - what are we building, in a sentence or a brain dump, messy is fine - and wait. Do not invent a task, and do not substitute a repo TODO for an answer.

## Start

With a green preflight and an idea in hand, start the fleet's intake as the lead's routing says: an unshaped idea goes to `spec-writer`, whose interview opens the problem out before the spec closes it down - the `spec-to-plan` flow. Recall from the memory server and send `scout` ahead if the idea touches existing code, then spawn `spec-writer` with the idea verbatim, not paraphrased. From there the normal pipeline holds: the human edits the spec, the plan is written and approved, and only then does a `coder` run.

Report the preflight result either way - one line per check when green, the failure list when not.
