# <FILL: project name>

<FILL: one sentence saying what this project is and who it serves.>

Every `<FILL: ...>` marker below is a placeholder. Replace it or delete the line.
A marker left in place is a line Claude reads literally on every turn.

This file holds only what must be true on every turn and fits in a sentence:
stack, conventions, the glossary pointer, and where specs and plans live. It stays
under 200 lines. Procedures are skills, not entries here. Conventions that apply
only to some files belong in `.claude/rules/<name>.md` with a `paths:` header, so
they load when those files are open rather than always.

## Stack

- Language and runtime: <FILL: e.g. TypeScript on Node 22>
- Framework: <FILL: e.g. Electron plus React 19>
- Data: <FILL: e.g. Drizzle over SQLite>
- API: <FILL: e.g. Fastify>
- Styling: <FILL: e.g. Tailwind>
- Tests: <FILL: e.g. Vitest, run with npm test>
- Build and run: <FILL: the one command that builds and the one that runs>

## Conventions

<FILL: the handful of rules that must hold on every turn. One sentence each, no
procedures. Examples of the shape: tests go beside the code they cover; no default
exports; every database change ships with a migration; never edit generated files.>

Never edit `.env` or any file holding a credential.

## Glossary

The project glossary is `.claude/rules/glossary.md` and loads on every turn. Use its
words with its meanings, and if a term you need is missing, say so rather than
inventing one. That file is generated from the `glossary` skill in `claude-agents`,
so never edit it here - change the skill and regenerate.

## Where work lives

Specs live at `docs/specs/<issue>.md`, one file per issue, written by `spec-writer`.

Plans live at `docs/plans/<issue>.md`, one file per issue, written with the built-in
Plan agent and approved by Alex before any code is written.

An issue number in a branch name, a commit or a handoff refers to the same issue as
those two files. If a spec or a plan is missing, say so rather than proceeding from
a guess.

<FILL: anything else with a fixed home, e.g. ADRs in docs/adr/, runbooks in docs/runbooks/.>

## Writing conventions

Australian English: organise, behaviour, colour, recognise, analyse.

Standard hyphens for asides - like this. Never an em dash, never an en dash. This is
a hard rule and the most common thing to get wrong.

No emojis, anywhere, in code, comments, commits or prose.

Say the thing once. Prefer the shorter sentence.

<FILL: project-specific writing rules, e.g. commit message format, changelog style.>
