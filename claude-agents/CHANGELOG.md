# Changelog

All notable changes to the `claude-agents` plugin are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the plugin uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

The version in `.claude-plugin/plugin.json` is load-bearing. Clients keep the
cached copy of the plugin until that number changes, so every change that should
reach a machine needs a version bump and an entry below.

## [0.4.0] - 2026-09-09

### Changed

- **MCP server identifiers now match what `claude mcp list` registers.** The
  memory server, Notion and Hugging Face reach the fleet as claude.ai
  connectors, so every body's `tools` and `disallowedTools` entry uses the
  `mcp__claude_ai_Memory__`, `mcp__claude_ai_Notion` and
  `mcp__claude_ai_Hugging_Face` spellings. The previous `mcp__rzem-memory__`,
  `mcp__Notion` and `mcp__Hugging_Face` entries named servers that were not
  registered and granted nothing, silently. `docs/agent-contract.md` section 6
  records the confirmed names and the date.
- `coder` no longer lists Context7. The server is not installed on any machine
  yet; the contract says how to add it back once `claude mcp list` shows it.
- The contract drops the "never reuse a colour" rule: the field accepts eight
  values and the fleet has nine agents.
- The plan moved from an untracked `tmp/` file into `README.md`, where plan
  section 10 always said it lived, with its roster, tree and settings examples
  corrected to match the repo.
- The contract now says which preloaded skills resolve today and which are
  forward references, since fourteen of the twenty-one names the bodies carry
  are not installed anywhere yet.
- **The glossary has two copies, not three.** The Notion copy was never built,
  and the one agent named to republish it, `fleet-steward`, blocks
  `notion-update-page` in its own `disallowedTools`. The `glossary` skill, the
  CLAUDE.md template and plan section 8 no longer mention it.
- **The quarterly pass over a project's `.claude/rules/` and `docs/runs/` is
  the lead's**, run when Alex asks for it, and the `compound` skill now
  describes it. It had been assigned to `fleet-steward`, which may not touch
  anything outside the claude-agents working copy.
- `fleet-steward`'s editing list names everything its four jobs already touch:
  agent bodies, the contract, skill frontmatter, the plugin manifest, the
  changelog, the plan in README.md and the generated glossary rule.

## [0.3.0] - 2026-09-08

### Added

- **Run articles.** A new discovered skill, `skills/run-article/`, and a home for
  what it produces at `docs/runs/`. An article is the readable account of one
  run - what was tried and abandoned, what the constraint turned out to be, what
  to do differently - which is everything the handoff cannot carry and which
  evaporates when the transcript scrolls. It is written only when the lead asks
  for one in the spawn prompt, per `agents/lead.md` steps 5 and 6, and never on
  the agent's own judgement. The skill is discovered rather than preloaded,
  because preloading a rarely used procedure into nine agents is paid on every
  spawn.
- `coder` and `ui-designer` write their article to `docs/runs/` and name the path
  in a Done bullet; `reviewer` and `researcher` create no files, so they return
  it above the handoff, where preamble prose is already tolerated, and the lead
  saves it. `scout`, `spec-writer`, `tech-writer` and `fleet-steward` are
  untouched, for the reasons in `docs/runs/README.md`.
- **Nothing was added to the handoff format for this, and the run-article
  change touched no hook.** The article path reaches the board card because
  `SubagentStop` already comments the `## Done` section verbatim on a clean run.
- `Run article` in the `glossary` skill and the generated
  `templates/rules/glossary.md`, and a short section in `compound` so the end of
  a unit of work reads articles as well as state-directory archives.

### Changed

- **Every board transition now puts a comment on the card**, lifted from the
  handoff and from the status the harness sends: the `## Done` items on a clean
  finish, the `## Not done` items plus the status on a failure or cancellation,
  the `Blocker:` lines on the human queue, and the test command with the tail of
  its output when the `TaskCompleted` gate fails. `SubagentStop` posts the Done
  comment because it is the only hook that ever sees a handoff; the move to Done
  stays with `TaskCompleted`. `hooks/lib/notion.sh` gained `board_comment`, and
  a comment is cut to `NOTION_COMMENT_MAX_CHARS` (default 8000, set in
  `board.env`) and sent in 1900-character chunks, so a long handoff never loses
  the whole comment to a Notion 400.
- **A cut comment is archived whole before it is cut**, at
  `~/.local/state/claude-agents/archives/<session>/<stamp>-<agent>.md`, and the
  note on the card names that file. The note used to point at a "run
  transcript" that nothing wrote. `BOARD_DRY_RUN=1` now prints the whole comment
  to stderr and still writes the archive. The `board` and `compound` skills say
  where the archives are and what to do with them.
- `fleet-steward` files what its scheduled sweep finds as board items itself,
  the one named exception to "the lead files proposals", because there is no
  lead in the loop on an unattended run. Its `disallowedTools` still block every
  Notion write except creating a row and commenting on one, and `agents/lead.md`
  step 5 no longer re-files what the steward lists under Done.

## [0.2.0] - 2026-09-08

The first release with content in it. The plugin now carries nine agents, five
skills, four hooks and three workflows, and the repo around it carries the evals,
the templates and the user-scope files the plan calls for.

### Added

- **Nine agents** in `agents/`, one per role in section 4 of the plan: `lead`,
  `scout`, `spec-writer`, `coder`, `reviewer`, `ui-designer`, `tech-writer`,
  `researcher` and `fleet-steward`. Each names its model, effort, tool allowlist
  and preloaded skills, states its own Invariants, and ends its work with the
  four-heading handoff. `docs/agent-contract.md` is the shape they all conform to.
- **Five skills** in `skills/`: `glossary`, the canonical copy of the shared
  vocabulary; `handoff`, the four-heading format with typed Decisions needed
  lines; `board`, the Notion column semantics and item conventions;
  `migration-checklist`, what to re-check in every body when a model ships; and
  `compound`, writing learnings back into rules and skills at the end of a unit
  of work.
- **Four hooks** in `hooks/`, registered by `hooks/hooks.json`:
  `board-subagent-start.sh` on `SubagentStart` binds the subagent to a board item
  and moves it to Doing; `board-subagent-stop.sh` on `SubagentStop` writes Blocked
  or Blocked by human and checks the handoff format; `board-task-completed.sh` on
  `TaskCompleted` runs the test gate and writes Done or Blocked; and
  `enforce-agent-scope.sh` on `PreToolUse` denies the tool calls an agent's own
  Invariants forbid, which is the per-agent scoping that session-scoped
  `permissions.deny` cannot express. `hooks/lib/notion.sh` holds the token
  handling, the Notion calls and the state files, and `hooks/README.md` documents
  the lot.
- **Three workflows** in `workflows/`: `spec-to-plan`, `review-round` and
  `deep-research`.
- **Nine smoke evals** under `evals/`, one per agent, each with three to five
  prompts, a rubric, mechanical checks and a baseline, plus `evals/run.sh` and the
  shared handoff gate in `evals/lib/`.
- `home/settings.json`, the user-scope permissions, sandbox and network policy
  installed by `scripts/install-home.sh`.
- `scripts/gen-glossary-rule.sh`, which generates `templates/rules/glossary.md`
  from the `glossary` skill so the rule and the skill cannot drift, and
  `scripts/install-home.sh`, which copies `home/` into `~/.claude`.
- `templates/CLAUDE.md`, the project skeleton with the glossary pointer;
  `templates/project-settings.json`, which now sets `agent` to
  `claude-agents:lead` as well as declaring the marketplace and enabling the
  plugin, so a project set up from the template gets the delegation policy and not
  just the plugin; and `templates/rules/glossary.md`, generated, never edited.

### Fixed

- The `SubagentStop` registration in `hooks/hooks.json` now carries a matcher, so
  the handoff gate applies to fleet agents only. Without it the gate fired on
  every subagent, including the `Plan`, `general-purpose` and unnamed lanes the
  workflows spawn, which return structured JSON rather than a handoff and so hit
  exit 2 and looped.
- `scout`, `spec-writer` and `fleet-steward` no longer name `permissions.deny` as
  the enforcement for their per-agent scoping. It is session-scoped and cannot
  express a rule that binds one agent, and two of the three entries cited did not
  exist. The Invariants now name `hooks/enforce-agent-scope.sh`, which is what
  actually enforces them.
- The `0.1.0` entry below no longer says the component directories are empty.
  They have not been since the agents landed, and a changelog that says otherwise
  is the first thing a reader believes.

## [0.1.0] - 2026-09-08

Initial scaffolding. The repo became a plugin marketplace with one plugin in it.

### Added

- `.claude-plugin/marketplace.json` at the repo root, declaring the `rzem`
  marketplace with a single plugin, `claude-agents`, sourced from the
  `./claude-agents` directory. Installed as `claude-agents@rzem`.
- `claude-agents/.claude-plugin/plugin.json` at version `0.1.0`, with the plugin
  name, description, author and repository. Component directories are left to
  auto-discovery rather than named explicitly, so the defaults apply.
- The directory structure the plan calls for: `agents/`, `skills/`, `hooks/` and
  `workflows/` inside the plugin, and `evals/`, `scripts/`, `templates/`,
  `templates/rules/` and `home/` in the repo.
- This changelog.

[Unreleased]: https://github.com/rzem-ai/claude-agents/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/rzem-ai/claude-agents/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/rzem-ai/claude-agents/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rzem-ai/claude-agents/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rzem-ai/claude-agents/releases/tag/v0.1.0
