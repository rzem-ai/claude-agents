# Changelog

All notable changes to the `claude-agents` plugin are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the plugin uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

The version in `.claude-plugin/plugin.json` is load-bearing. Clients keep the
cached copy of the plugin until that number changes, so every change that should
reach a machine needs a version bump and an entry below.

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
- **Nothing was added to the handoff format and no hook changed.** The article
  path reaches the board card because `SubagentStop` already comments the
  `## Done` section verbatim on a clean run.
- `Run article` in the `glossary` skill and the generated
  `templates/rules/glossary.md`, and a short section in `compound` so the end of
  a unit of work reads articles as well as state-directory archives.

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

[Unreleased]: https://github.com/rzem-ai/claude-agents/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/rzem-ai/claude-agents/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rzem-ai/claude-agents/releases/tag/v0.1.0
