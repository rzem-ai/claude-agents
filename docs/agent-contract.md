# Agent contract

Every agent body in `claude-agents/agents/` conforms to this file. `claude-agents/agents/reviewer.md` is the worked exemplar - read it alongside this.

`docs/` is not in the plan's section 10 tree. It is added deliberately: section 11 has the `fleet-steward` running the `migration-checklist` skill over every agent body each time a model ships, and a checklist needs something to check against. This is that thing. When a frontmatter field is added or renamed upstream, the steward's PR updates this file first and the nine bodies second.

Verified against `https://code.claude.com/docs/en/sub-agents` on 8 September 2026. Field names below are the real ones, not the plan's table headings.

## 1. Frontmatter

The file is a markdown file with a YAML frontmatter block delimited by `---`. Everything after the closing `---` is the agent's system prompt.

### Fields the fleet uses

| Field | Type | Allowed values | Required | Notes |
|---|---|---|---|---|
| `name` | string | lowercase letters and hyphens | yes | Must equal the filename without `.md` and the roster row's agent name |
| `description` | string | free text, one or two sentences | yes | This is routing copy. The lead reads it to pick an agent, so say what the agent does and when to use it |
| `model` | string | `opus`, `sonnet`, `haiku`, `fable`, `inherit` | no | Alias only. Never a pinned model ID (principle 3). Omitting it inherits the session model, which is not the same as `inherit` being wrong - be explicit |
| `effort` | string | `low`, `medium`, `high`, `xhigh`, `max` | no | Overrides session effort. Omit only where the roster says n/a |
| `tools` | comma-separated string on one line | tool names, `Agent(type)`, `mcp__<server>`, `mcp__<server>__*`, `mcp__<server>__<tool>` | no | An allowlist. Omitting it inherits every tool, which no fleet subagent should do. Not a YAML list - a single comma-separated line |
| `disallowedTools` | comma-separated string on one line | same syntax as `tools` | no | Subtracts from the inherited or allowed set. Use it only as a second lock on a stated invariant |
| `skills` | YAML list | skill names | no | Preloads the full skill body at startup. Every fleet agent lists at least `glossary`, `handoff` and `using-memory` |
| `color` | string | `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan` | no | Cosmetic; makes an agent findable in the task list. Pick one per agent and do not reuse |
| `isolation` | string | `worktree` | no | Only `coder` sets it |
| `memory` | string | `user`, `project`, `local` | no | **No fleet agent sets this.** See 1.3 |

### Fields that exist but the fleet does not use

`permissionMode`, `mcpServers` and `hooks` are ignored when an agent is loaded from a plugin, so they never appear in a shared body. An agent that genuinely needs one exists as a local copy under `home/agents/` instead (plan section 4). `maxTurns`, `background`, `initialPrompt` and `experimental` are unused; do not add them without a reason recorded in the changelog.

### 1.3 Where the roster columns do not map cleanly

Four of the plan's section 4 columns do not survive contact with the real frontmatter. All nine bodies handle them the same way.

**Memory `none` is not a value.** `memory` accepts `user`, `project` or `local` and nothing else. "Memory: none" in the roster means *omit the field entirely* - the agent then launches with no memory directory and no memory instructions, which is exactly what section 6 wants, because per-agent memory lives on the rzem-memory server instead. Leave a comment line in the frontmatter saying the omission is deliberate, so the steward does not read it as an oversight and a future reviewer does not add `memory: local` to be helpful.

**Isolation `none` is not a value either.** `isolation` accepts only `worktree`. Omit the field for the eight agents that are not `coder`.

**Bash cannot be scoped to git.** The `tools` field has no command-level specifier - there is no `Bash(git:*)`. `Bash` is all of Bash or none of it. So "Bash (git only)" and "Bash (read-only)" in the roster become two things working together: `Bash` in `tools`, plus an explicit invariant line in the body naming the git verbs that are forbidden. Real enforcement is host-level `permissions.deny` (plan section 12), not frontmatter. Say this in the body rather than pretending the frontmatter did it.

**Write cannot be scoped to a path.** Same shape of problem: "Write (docs/specs only)" is `Write` in `tools` plus a body invariant naming the directory. The same applies to `Edit` scoped to one repo.

One more that is not a column but bites everywhere: **"MCP (read)" needs explicit tool names.** `mcp__rzem-memory__*` grants the write tools too. A read-only memory agent lists the read tools individually - `memory_search`, `memory_read_document`, `memory_tree`, `memory_kv_get`, `memory_kv_list` - and may repeat the write tools under `disallowedTools` as a second lock. Only `researcher` and the lead get `memory_capture`.

## 2. Body structure

Four H2 sections, in this order, after an unheaded opening. No H1. No other headings.

**Opening**, unheaded, one paragraph. Who the agent is and what it returns, in the second person. If the agent sits in a pipeline, say what runs before and after it, so it does not redo work another stage already did. Three to five sentences.

**`## Scope`.** What is in, then what is out. The out-of-scope paragraph is the load-bearing one - it is where you stop an agent drifting into another agent's job. Two short paragraphs.

**`## How you work`.** The procedure, as a numbered list. Six steps or fewer, one line each where possible. Steps name the tools and skills to use at each point. This is the only section where a numbered list is right; do not bullet the others.

**`## Invariants`.** The never-lines, one per line, no bullets. This is the section 8 exception: a three-line invariant is cheaper in the body than as a preloaded skill. Keep it to four or five lines, all absolute, none conditional. If an invariant needs a paragraph to explain, it is a skill, not an invariant.

**`## Handoff`.** One paragraph. State that the handoff is required and that all four headings must be present, then map this agent's output onto the headings and say which findings become `Blocker:` and which become `Propose item:`. Do not restate the format - `handoff` is preloaded and the format lives there.

## 3. Hard rules

Under 60 lines total, frontmatter included. The exemplar is 44. If you cannot fit, the body is carrying something that belongs in a skill.

Never paste skill text into a body (principle 2). Reference a preloaded skill by name in backticks and trust that it is in context. If you find yourself explaining what `handoff` or `review-checklist` says, delete the explanation.

No conditional model or effort logic. Nothing of the shape "if the diff touches auth, use xhigh" or "escalate to Fable for architecture work". All escalation lives in the lead's delegation policy, because that is where the decision is actually made, and an agent cannot change its own model mid-run anyway. The frontmatter values are static.

No personas. These are role names doing a job, not characters. No name, no backstory, no personality. Personas are Sprites and Sprites are out of scope.

The handoff section is mandatory in every body.

Invariants are terse body lines, never a preloaded skill and never a paragraph.

Every agent preloads `glossary`, `handoff` and `using-memory` at minimum, and uses the glossary's words with the glossary's meanings.

No agent writes to the board. Board columns are written by hooks (plan section 7). A body that tells an agent to update a status is wrong.

## 4. Writing conventions

Australian English: organise, behaviour, colour, recognise, analyse.

Standard hyphens for asides. Never an em dash, never an en dash. This is a hard rule and the most common thing to get wrong.

No emojis, anywhere, ever.

Bullets only when the content is genuinely list-shaped. `## How you work` is a numbered list because steps are ordered. `## Scope` and `## Handoff` are prose. `## Invariants` is one sentence per line without bullet markers, because it reads as a list of prohibitions rather than a list of items.

Second person throughout the body. "You review a diff", not "The reviewer reviews a diff" and not "I will review".

Say the thing once. If the opening already said the agent never edits, the invariant says it in different words or not at all.

## 5. Checklist before you commit a body

The `migration-checklist` skill runs a superset of this. Minimum, every time:

1. `name` matches the filename and the roster row.
2. `model` is an alias, not an ID.
3. `effort` matches the roster row.
4. `tools` is a comma-separated line, is an allowlist, and expands any "MCP (read)" into named read tools.
5. `memory` and `isolation` are absent unless the roster row genuinely asks for `worktree`.
6. `skills` includes `glossary`, `handoff` and `using-memory`.
7. Four H2 sections, in order, and no others.
8. Under 60 lines.
9. No pasted skill text, no conditional model or effort logic, no persona.
10. No em dashes, no en dashes, no emojis, Australian spelling.

## 6. MCP server names

A `tools` line grants an MCP server by the name Claude Code registered it under - `mcp__<server>` for the whole server, `mcp__<server>__<tool>` for one tool. The name is case-sensitive and nothing normalises it. A body naming a server that does not exist grants nothing, raises no error and prints no warning: the agent just runs without those tools, and the first sign of trouble is a `researcher` that cannot reach Hugging Face or a `spec-writer` that cannot read the board. A wrong server name is a silent no-op, which is why it belongs in this file rather than in someone's memory.

The fleet uses four servers:

| Server | Granted as | Carried by | Where the name came from |
|---|---|---|---|
| `rzem-memory` | `mcp__rzem-memory__<tool>` | all nine agents | Alex's own server, named in his MCP config. Authoritative |
| `Notion` | `mcp__Notion` | `spec-writer`, `fleet-steward`, the lead | Observed in a live connector session |
| `Hugging_Face` | `mcp__Hugging_Face` | `researcher` | Observed in a live connector session |
| `Context7` | `mcp__Context7` | `coder` | Observed in a live connector session |

Only `rzem-memory` is confirmed. The other three are transcribed from an observed connector session, which is the best evidence available and is still not the same thing as Alex's Claude Code MCP configuration: a connector's display name and the key Claude Code registers it under can differ, and the underscore in `Hugging_Face` is exactly the sort of detail that a rename or a different transport would change. Confirm all three against `claude mcp list` and the relevant `.mcp.json` before the first run, and if one differs, correct this table and the body that names it in the same change.

Two scoping notes that go with the names. `rzem-memory` reaches all nine agents deliberately (plan section 6); every other server stays scoped, because an MCP server's tool list is paid for on every turn of every agent that carries it. And `Context7` is granted in the shared `coder` body as a tool allowlist entry only - the server itself is wired in the local copy under `home/agents/`, because a plugin agent cannot set `mcpServers` (plan section 9).
