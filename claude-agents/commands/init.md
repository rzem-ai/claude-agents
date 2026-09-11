---
description: Initialise the current project for the fleet - settings, CLAUDE.md skeleton, glossary rule, spec and plan directories, then a guided fill of every placeholder
---

Initialise this project for the claude-agents fleet. Work through the four steps in order, report at the end, and never overwrite anything the project already has.

Templates live in this plugin at `${CLAUDE_PLUGIN_ROOT}/templates/`. Read each one from there; never reconstruct its content from memory.

## 1. Settings

Merge the three keys from `${CLAUDE_PLUGIN_ROOT}/templates/project-settings.json` into the project's `.claude/settings.json`:

- `agent` (`claude-agents:lead`)
- `extraKnownMarketplaces.rzem`
- `enabledPlugins["claude-agents@rzem"]`

If `.claude/settings.json` does not exist, copy the template as-is. If it exists, add only the keys that are missing and leave every existing key exactly as it is - including an existing `agent`, an existing `rzem` marketplace entry, and any other plugins. A key that is present but differs from the template is a conflict: report it and leave it alone rather than changing it.

## 2. Skeleton

- `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md` -> `CLAUDE.md` at the project root. If a `CLAUDE.md` already exists, do not touch it - note the skip and, in the final report, list which sections of the template (stack, conventions, glossary pointer, where work lives, writing conventions) the existing file lacks, so the human can decide what to add.
- `${CLAUDE_PLUGIN_ROOT}/templates/rules/glossary.md` -> `.claude/rules/glossary.md`. If it exists but differs from the template, replace it - the file is generated and the plugin's copy is current; never hand-merge it.
- Create `docs/specs/` and `docs/plans/` if missing.

## 3. Guided fill

Skip this step entirely if step 2 skipped `CLAUDE.md`.

Read the project before asking anything: manifest and lockfiles (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod` or equivalent), build and test configuration, the directory layout, and the last dozen commit subjects. Draft an answer for every `<FILL: ...>` marker in the copied `CLAUDE.md` from that evidence.

Then walk the markers with the human using the AskUserQuestion tool, one topic per question, offering the inferred value as the recommended option. Markers you could not infer get an open question, not a guess. Write each confirmed value into `CLAUDE.md` as you go, and delete the marker-explainer paragraph near the top once no markers remain.

If the human declines the interview, fill the markers you inferred with confidence, leave the rest as `<FILL: ...>`, and say which remain.

## 4. Report

End with a short report: what was created, what was merged and which keys, what was skipped and why, any settings conflicts, and any markers still unfilled. Remind the human to commit `.claude/settings.json` (and the rest) so every clone and every Claude Code on the web session gets the same fleet.

Then say what comes next, exactly: restart Claude Code and trust the folder - the new settings, `CLAUDE.md` and (if it was not already installed) the plugin all load at session start, so nothing done here is live until then - and in the new session run `/claude-agents:kickoff` to verify the install and start the first piece of work.

Re-running this command is safe: every step skips what already exists, and step 3 only offers markers still present.
