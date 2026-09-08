# Changelog

All notable changes to the `claude-agents` plugin are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the plugin uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

The version in `.claude-plugin/plugin.json` is load-bearing. Clients keep the
cached copy of the plugin until that number changes, so every change that should
reach a machine needs a version bump and an entry below.

## [Unreleased]

## [0.1.0] - 2026-09-08

Initial scaffolding. The repo is now a plugin marketplace with one plugin in it,
but the plugin has no content yet: agents, skills, hooks and workflows land in
later releases.

### Added

- `.claude-plugin/marketplace.json` at the repo root, declaring the `rzem`
  marketplace with a single plugin, `claude-agents`, sourced from the
  `./claude-agents` directory. Installed as `claude-agents@rzem`.
- `claude-agents/.claude-plugin/plugin.json` at version `0.1.0`, with the plugin
  name, description, author and repository. Component directories are left to
  auto-discovery rather than named explicitly, so the defaults apply.
- The directory structure the plan calls for: `agents/`, `skills/`, `hooks/` and
  `workflows/` inside the plugin, and `evals/`, `scripts/`, `templates/`,
  `templates/rules/` and `home/` in the repo. Each carries a `.gitkeep` while it
  is empty.
- This changelog.

[Unreleased]: https://github.com/rzem-ai/claude-agents/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rzem-ai/claude-agents/releases/tag/v0.1.0
