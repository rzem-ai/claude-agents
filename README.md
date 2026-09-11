# claude-agents

A personal Claude Code subagent fleet: ten role-shaped agents delegated to from a Claude Code session, the skills they share, the hooks that keep a Notion board honest, and the evals that catch a regression before a model release does. The repo is a Claude Code plugin marketplace with one plugin, and it is the single source of truth - every machine and cloud session that runs the fleet gets it from here.

The agents are roles, not personas: disposable by design, with fresh context on every spawn and their memory on a server rather than in their heads. The fleet also maintains itself - a `fleet-steward` agent watches model releases and files PRs against this repo, and most substantial changes here were produced by the fleet's own workflows, then reviewed the same way any other change would be.

## The fleet

| Agent | Job |
|---|---|
| `lead` | Plans, routes and gates. Runs as the main session (the `agent` key in project settings), never spawned |
| `scout` | Cheap read-only reconnaissance: where is X, how does Y work. Locations and excerpts, never opinions |
| `spec-writer` | Turns a brain dump or a board item into a spec, interviewing first |
| `coder` | Implements one approved plan phase, tests first, in its own git worktree |
| `reviewer` | Reviews a diff for correctness, design and security. Reports, never edits |
| `refuter` | Tries to break what was just built and reports what broke it. Never fixes |
| `ui-designer` | Screens, flows and HTML prototypes from a spec |
| `tech-writer` | READMEs, ADRs, runbooks and drafts from material that already exists |
| `researcher` | Fan-out reading and synthesis with citations |
| `fleet-steward` | Weekly model and tooling sweep. Files PRs, never merges |

Each body in [`claude-agents/agents/`](claude-agents/agents/) carries its model, effort, tool allowlist, preloaded skills and invariants; the reasoning behind every choice is in the plan, section 4.

## How it works

**Every agent ends with the same handoff.** Four headings - Done, Not done, Unverified, Decisions needed - with typed lines under the last (`Blocker:`, `Propose item:`, `Propose memory:`), so the lead can merge a stack of handoffs without re-reading a stack of transcripts. The format is the `handoff` skill, preloaded everywhere and enforced by a hook.

**Hooks write the board; agents never do.** `SubagentStart` moves a Notion board item to Doing, `SubagentStop` writes Blocked or Blocked by human (a `Blocker:` line in the handoff is what lands in the human queue), and `TaskCompleted` gates on tests before writing Done. A fourth hook, `enforce-agent-scope.sh`, denies at `PreToolUse` the tool calls each agent's own invariants forbid - the per-agent boundary that session-scoped permissions cannot express.

**Workflows chain the roles.** `spec-to-plan`, `review-round` and `deep-research` in [`claude-agents/workflows/`](claude-agents/workflows/) run the multi-agent shapes deterministically instead of hoping the model sequences them.

**Everything is evalled.** Each agent has a smoke eval under [`evals/`](evals/) run with `claude -p`, and `evals/lib/check-all.sh` runs every deterministic check - hook contracts, roster consistency, workflow logic - with no model, no network and no Notion.

## Using it

**Wire a project.** Copy [`templates/project-settings.json`](templates/project-settings.json) into the repo's `.claude/settings.json`. On folder trust, the marketplace is known, the plugin installs, and the session runs as the lead. That is the whole per-project story, and it is what makes Claude Code on the web work too.

**Set up a machine.** `scripts/install-home.sh` copies `home/` into `~/.claude` (settings, CLAUDE.md, rules, local agent copies) and renders the fleet secrets from 1Password into `~/.config/claude-agents/`. Run with `--dry-run` first, or `--home-only` to skip the secrets - the 1Password references are placeholders until the fleet vault exists.

**Stay current.** The plugin is semver'd and the version in `claude-agents/.claude-plugin/plugin.json` is load-bearing: clients keep the cached copy until the number changes. `claude plugin marketplace update rzem` picks up a new release.

**Check a change.** `bash evals/lib/check-all.sh` before anything else; `evals/run.sh` for the model-in-the-loop smoke evals.

## Repo map

```
.claude-plugin/marketplace.json   the marketplace (name: rzem), one plugin in it
claude-agents/                    the plugin: agents/, skills/, hooks/, workflows/, CHANGELOG.md
evals/                            one smoke eval per agent, plus lib/ with the deterministic suite
docs/fleet-plan.md                the plan: what the fleet is and why, in fifteen sections
docs/agent-contract.md            the shape every agent body conforms to
docs/runs/                        run articles, one per substantial run
docs/plans/                       per-issue implementation plans (the glossary kind, not the fleet plan)
docs/TODO.md                      open items each round has deliberately left, with the reason
home/                             user-scope files the install script places
scripts/                          install-home.sh, gen-glossary-rule.sh, merge-settings.py
templates/                        project settings, CLAUDE.md skeleton, the generated glossary rule
```

## Where things are decided

The plan, [`docs/fleet-plan.md`](docs/fleet-plan.md), is the canonical document - "plan section N" anywhere in this repo means that file. [`docs/agent-contract.md`](docs/agent-contract.md) is what the migration checklist checks agent bodies against, and it records which preloaded skill names are still forward references. [`claude-agents/CHANGELOG.md`](claude-agents/CHANGELOG.md) records every release, corrections included. And [`docs/TODO.md`](docs/TODO.md) is the open-items list: what each round has looked at and deliberately chosen to leave, with the reason.
