---
description: Preflight the fleet in this project - plugin, agents, settings, skeleton - check or set up the Linear board and state its conventions, then take the first idea and start the spec pipeline on it
argument-hint: [the idea, in a sentence or a brain dump]
---

Kick off fleet work in this project. Run the preflight first, and start work only if it comes back green. This command is what `/claudecode-agents:init` points at after its restart, so assume nothing - the point of the preflight is to catch a half-finished setup.

## Preflight

Check each of these, collecting results rather than stopping at the first failure:

1. **Plugin.** The claudecode-agents agents are available (`scout`, `spec-writer`, `coder`, `reviewer`, `refuter`, `ui-designer`, `tech-writer`, `researcher`, `fleet-steward` and `lead` appear as `claudecode-agents:` agent types). If they are missing, the plugin is not installed or the marketplace cache is stale.
2. **Lead.** `.claude/settings.json` exists and sets `agent` to `claudecode-agents:lead`. Note, without failing, if the current session is visibly not running as the lead - that means the settings changed since the session started and a restart is needed.
3. **Skeleton.** `CLAUDE.md` exists at the project root and contains no `<FILL: ...>` markers. A marker left in place is a line the session reads literally on every turn, so surviving markers are a failure, not a note.
4. **Glossary rule.** `.claude/rules/glossary.md` exists.
5. **Work directories.** `docs/specs/` and `docs/plans/` exist.
6. **Board.** The full check-and-setup is its own step below; here just note whether the Linear tools are available at all. No Linear connector means no board, which is fine and is not a failure.

If anything failed: report every failure with its one-line fix (`/claudecode-agents:init` for missing skeleton pieces, restart-and-trust for a plugin or agent problem, edit the marker for a surviving `<FILL: ...>`), and stop. Do not start work on a red preflight.

## Board

Run this step only when the Linear tools are available. Read the `board` skill first; it is the contract this step is verifying. No board is a legitimate outcome throughout - most work is not board work, and the human declining any part of this is a note in the report, never a failure.

**Check.** Resolve the workspace and its team, then verify the pieces the fleet leans on:

- The team's workflow states cover the five columns - `To do`, `Doing`, `Blocked`, `Blocked by human`, `Done`. The hooks match state names ignoring case and spaces, so `Todo` satisfies `To do`; anything further apart needs either a rename in Linear or a `BOARD_COL_*` override in `~/.config/claudecode-agents/board.env`, and the two fixes are not equivalent - the override leaves every other tool seeing the odd name. `Blocked` and `Blocked by human` are the ones a team usually lacks.
- A Linear project exists for this repo. Match by name against the repo, or by a label naming it.
- The outcome labels `outcome/shipped`, `outcome/abandoned` and `outcome/superseded` exist on the team.

**Setup.** Say what is missing and ask the human before creating anything - these are writes to their workspace. On a yes: create the project for this repo (with a label naming the repo) and the outcome labels. Workflow states are the one thing the Linear MCP cannot create - if `Blocked` or `Blocked by human` is missing, hand the human the exact instruction instead: add both in the team's workflow settings with the `started` type, since an item in either is picked up, not waiting to start.

**State the conventions.** End the board section by saying, concretely for this workspace, what the fleet will use - so the session and the human agree before the first issue is filed:

- the team and its key (which is what an issue ref like `RZE-123` carries),
- the project this repo's issues go in,
- the five column names as this team spells them, and any `BOARD_COL_*` override that implies,
- labels: the repo label on the project, `outcome/*` on issues at close, nothing else load-bearing,
- and the binding reminder: a board session launches with `CLAUDECODE_AGENTS_BOARD_PAGE_ID=<issue ref>`, and only a task subject carrying `[board:<issue ref>]` closes an issue.

**What this step cannot do, said out loud.** The hooks authenticate with their own API key at `~/.config/claudecode-agents/linear.token`, which every agent is denied by design - so this step can never test that key, and a board green here can still fail in the hooks. End with the one manual check: the key file exists at that path with mode 600 (rendered by `scripts/install-home.sh`). A `no board item` or HTTP-error line in `~/.local/state/claudecode-agents/log/hooks.log` after the first real spawn is the symptom of it missing.

## The idea

The text after the command is the idea. If there is none, ask the human one open question - what are we building, in a sentence or a brain dump, messy is fine - and wait. Do not invent a task, and do not substitute a repo TODO for an answer.

## Start

With a green preflight and an idea in hand, start the fleet's intake as the lead's routing says: an unshaped idea goes to `spec-writer`, whose interview opens the problem out before the spec closes it down - the `spec-to-plan` flow. Recall from the memory server and send `scout` ahead if the idea touches existing code, then spawn `spec-writer` with the idea verbatim, not paraphrased. From there the normal pipeline holds: the human edits the spec, the plan is written and approved, and only then does a `coder` run.

Report the preflight result either way - one line per check when green, the failure list when not.
