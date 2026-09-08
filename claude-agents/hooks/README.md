# Hooks

The machinery that writes the Notion board and enforces per-agent tool scoping.
Four hooks, one shared library, no agent ever asked to remember anything.

| File | Event | What it does |
|---|---|---|
| `board-subagent-start.sh` | `SubagentStart` | Binds the subagent to a board item and moves it to **Doing** |
| `board-subagent-stop.sh` | `SubagentStop` | **Blocked** on failure or cancellation, **Blocked by human** on a `Blocker:` line, a comment lifted from the handoff on every outcome, and the handoff-format check. Matched to the fleet agents only |
| `board-task-completed.sh` | `TaskCompleted` | Tests pass, **Done**. Tests fail, **Blocked** with the failure as a comment, and exit 2 |
| `enforce-agent-scope.sh` | `PreToolUse` | Denies tool calls that violate an agent's own Invariants |
| `lib/notion.sh` | - | Token handling, the Notion calls, state files, page-id parsing |
| `hooks.json` | - | Registers the four above with Claude Code |

Board writes are section 7 of the plan. `permissions.deny` is session-scoped, so
`enforce-agent-scope.sh` is the per-agent half that settings cannot express; it
is an addition to the plan, approved separately.

## Which board item

This is the part the plan left open. It says the hook "is expected to know the
item from the spawn context" and never says how, so here is the convention. The
lead is wired up to follow it: `agents/lead.md` step 6 and the `board` skill,
which both agents preload.

### The convention

**The lead puts a `Board-Item:` line in the spawn prompt of every subagent it
spawns against a board item.** One line, anywhere in the prompt:

```
Board-Item: 24f1a3b9c1d24e6f8a0b1c2d3e4f5061
```

The value is a Notion page id, dashed or undashed, or the page URL copied
straight out of Notion. `SubagentStart` reads it from the `instructions` field,
normalises it to a dashed UUID, and records it in a state file keyed by
`session_id` and `agent_id`. `SubagentStop` reads that file back. Nothing else
in the chain has to know anything.

A spawn with no `Board-Item:` line moves no column, logs one line saying so, and
exits 0. That is the correct behaviour for the `scout` you spawned to answer a
question: most spawns are not board items and should not touch the board.

### What must be wired up

1. ~~The lead's body, or the `board` skill, must tell the lead to emit that
   line.~~ Done, in both: `agents/lead.md` step 6 carries the rule and
   `skills/board/SKILL.md`, "Telling the hooks which item", carries the full
   convention. Neither is a file this layer owns, so if either is rewritten
   without that content, every board write goes back to being a no-op and the
   log fills with "no board item" lines.
2. ~~`scripts/install-home.sh` must render `~/.config/claude-agents/notion.token`
   at mode 600 (plan section 12).~~ Done. It rendered `notion-token` with a
   hyphen until 8 September 2026, which meant a correctly installed machine
   never had a token where `lib/notion.sh` looks for one.
3. The Tasks database needs a status property whose options are named exactly
   `To do`, `Doing`, `Blocked`, `Blocked by human`, `Done`. If they are spelled
   differently, override the names in `board.env` (below).

### The fallbacks, in order

`SubagentStart`:

1. `Board-Item:` in the spawn prompt.
2. `CLAUDE_AGENTS_BOARD_PAGE_ID` in the environment. Set this for a session that
   is working one issue end to end and you would rather not repeat yourself.
3. Nothing. No column moves.

`SubagentStop`: the state file for this `agent_id`, then the environment
variable, then nothing.

`TaskCompleted` has no `agent_id`, so it resolves differently:

1. A `[board:<page-id>]` marker anywhere in the task title.
2. The item most recently picked up in this session, from
   `sessions/<session_id>/last-item`.
3. `CLAUDE_AGENTS_BOARD_PAGE_ID`.
4. Nothing. The test gate still runs; no column moves.

Fallback 2 is the one to watch. A session juggling two board items at once will
attribute a completed task to whichever was picked up last. If you work two
items in one session, put the `[board:...]` marker in the task title and the
guess never happens.

### State files

```
${XDG_STATE_HOME:-~/.local/state}/claude-agents/
  sessions/<session_id>/agents/<agent_id>   page_id, agent_type, bound_at
  sessions/<session_id>/last-item           the most recent page id
  log/hooks.log                             every line the hooks log
  disabled                                  if this file exists, no board writes
```

Directories are 0700 and files 0600. Nothing here is secret, but nothing here is
anyone else's business either. Nothing prunes old sessions yet; they are a few
hundred bytes each.

## Configuration

Everything has a default. `~/.config/claude-agents/board.env` overrides them and
is sourced if it exists - same 0700 directory as the token, so it is already out
of reach of every agent via `permissions.deny`.

```sh
# ~/.config/claude-agents/board.env
NOTION_VERSION=2022-06-28
BOARD_STATUS_PROPERTY=Status        # the property the board view groups by
BOARD_STATUS_TYPE=status            # "status" or "select" - see below
BOARD_COL_TODO="To do"
BOARD_COL_DOING=Doing
BOARD_COL_BLOCKED=Blocked
BOARD_COL_BLOCKED_HUMAN="Blocked by human"
BOARD_COL_DONE=Done

NOTION_COMMENT_MAX_CHARS=8000       # how much of a card comment survives; see below

CLAUDE_AGENTS_TEST_COMMAND=""       # empty means fall through to the marker file
CLAUDE_AGENTS_TEST_GATE=lenient     # or "strict"
CLAUDE_AGENTS_TEST_TIMEOUT=300
CLAUDE_AGENTS_TEST_STATUS_MAX_AGE=3600
CLAUDE_AGENTS_REPO=""               # the claude-agents working copy, for fleet-steward
```

A Notion board can be grouped by a `status` property or by a `select` property,
and the PATCH body differs between them. The hooks try the configured type, and
on a 400 retry once with the other, logging which one worked so you can pin it
in `board.env` and skip the round trip.

Two escape hatches:

- `CLAUDE_AGENTS_BOARD=off`, or `touch ~/.local/state/claude-agents/disabled`,
  turns every board write into a log line. The test gate and the handoff check
  still run.
- `BOARD_DRY_RUN=1` logs what would have been written without calling Notion.
  This is how the tests below work.

## What the card says

A column on its own is a status light. Every transition also puts a comment on
the row, so a card answers what happened without anyone opening a transcript.

The text is lifted from things that already exist and are already mandatory: the
four handoff sections, the `status` field the harness sends, and, for the test
gate, the command it ran and the output it got. **Nothing was added to the
handoff format for this and nothing should be.** The format was made strict and
four implementations were brought into agreement over a 28-case fixture; an
optional fifth heading or a fourth typed prefix would decay the first time an
agent forgot it, which is the whole reason the board is machinery rather than
manners.

| Transition | Hook | The comment |
|---|---|---|
| Done | `SubagentStop`, clean success | `Done. <agent> finished with no blockers. From "## Done" in its handoff:` then the `## Done` items |
| Blocked, run failed or cancelled | `SubagentStop` | `Blocked. <agent> finished with status <status>. From "## Not done" in its handoff:` then the `## Not done` items |
| Blocked, no readable handoff | `SubagentStop` | `Blocked. <agent> finished with status <status>. Its handoff carried no readable "## Not done" detail, so the status is all this card can say.` |
| Blocked by human | `SubagentStop` | `Blocked by human. <agent> raised N blocker(s). From "## Decisions needed" in its handoff:` then the blocker lines |
| Blocked, tests failed | `TaskCompleted` | `Blocked. The test gate failed on "<task title>", so the task could not be marked complete.` then the command, its exit code and the tail of its output |

One shape throughout: a headline naming the transition and where the detail came
from, a blank line, then the lines themselves.

Three things worth knowing:

- **The Done comment is posted by `SubagentStop`, which still moves no column.**
  `TaskCompleted` owns the move to Done exactly as before, and it never sees a
  handoff. The only moment the agent's own account of the work exists is when
  the subagent stops, so that is where it is read and put on the card. Stashing
  the section for `TaskCompleted` to read later was the alternative and was
  rejected: its item resolution falls back to guessing, so a stale summary would
  land on whichever row was picked up last.
- **A section of nothing but `- None` earns no comment.** The extractor drops
  `- None`, and a caller with an empty body posts nothing at all. The failure
  path is the exception - it always comments, because the status itself is the
  news even when the handoff says nothing.
- **The failure path reads a handoff nobody validated.** The format check runs
  on success only, and still does. `extract_section` is deliberately tolerant:
  it returns the `- ` lines it can find and nothing if it finds none, which is
  what puts the agent-type-and-status fallback on the card.

### Comment length

Notion's [request limits](https://developers.notion.com/reference/request-limits)
cap one rich text object at **2000 characters** and any rich text array at
**100 elements**, inside a 500KB request. No limit is documented for comments
specifically, so the real ceiling on one comment is 100 x 2000 characters.

Nothing that belongs on a card is near that, and a request over either cap comes
back 400, which loses the whole comment rather than its tail. So `notion_comment`
cuts to `NOTION_COMMENT_MAX_CHARS` (default 8000) first and chunks at 1900 after:
five objects at the default, never near the array cap, with `NOTION_COMMENT_HARD_MAX`
clamping an over-generous `board.env` value back to 95 chunks. The cut happens
inside `jq`, which counts Unicode codepoints the way Notion's limit does, so a
multi-byte character is never split in half. A cut comment ends with a line
saying how many characters were left off and that the rest is in the run
transcript, and the hook logs the same. No comment is ever posted empty.

## The handoff-format check

### Who it applies to

`SubagentStop` takes a matcher and the matcher is the agent type, so `hooks.json`
registers this hook against the nine fleet agents and nothing else:

```
^(claude-agents:)?(lead|scout|spec-writer|coder|reviewer|ui-designer|tech-writer|researcher|fleet-steward)$
```

The optional prefix is there because a plugin agent arrives as `scout` or as
`claude-agents:scout` depending on how it was named.

Without the matcher the gate fired on every subagent, including the built-in
`Plan` and `general-purpose` lanes the workflows spawn. Those lanes never preload
the `handoff` skill and are asked for structured JSON, so every one of them
failed the check, hit exit 2 and was told to re-emit a handoff it was never asked
for. Scoping the registration is the fix rather than a special case inside the
validator, because a lane that returns JSON is not a malformed handoff - it is
not a handoff at all.

The cost is that a non-fleet subagent no longer moves a bound board item to
Blocked when it fails. That only matters for a spawn carrying a `Board-Item:`
line, and the lead only binds those to fleet agents.

### What it checks

`board-subagent-stop.sh` validates `last_assistant_message` against
`skills/handoff/SKILL.md` and exits 2 if it does not parse, which stops the
subagent stopping and hands it the list of problems. The anchors come from the
skill, quoted rather than reinvented:

| Rule | Regex | Line in `skills/handoff/SKILL.md` |
|---|---|---|
| Section headings | `^## (Done\|Not done\|Unverified\|Decisions needed)$` | "Anchor: `^## (Done\|Not done\|Unverified\|Decisions needed)$`" |
| Any level-2 heading | `^## ` | "Use no other level-2 heading anywhere in the final message." |
| An item | `^- ` | "Every item is one markdown list item starting `- ` at column 0." |
| A typed line | `^- (Blocker\|Propose item\|Propose memory): ` | "Anchor: `^- (Blocker\|Propose item\|Propose memory): `" |
| An empty section | `^- None$` | "An empty section contains exactly one line: `- None`." |
| Where a typed line may appear | `^- (Blocker\|Propose item\|Propose memory): ` under `## Decisions needed` only | "A typed line belongs under `## Decisions needed` and nowhere else." |
| A blank line inside a section | a blank line with another item after it, before the next heading | "No blank line inside a section." |

What it rejects: a missing, duplicated or out-of-order heading; any other H2; an
empty section; a line under a section that does not start with `- ` at column 0,
which is also how "the handoff is the last thing in the message" is enforced;
an untyped line under Decisions needed; a typed line under any heading other
than Decisions needed; a blank line between two items in the same section; and
`- None` mixed with real items.

What it tolerates on purpose:

- **Prose before `## Done`.** The skill says the handoff is the last thing in
  the message, not the only thing. Nothing above the first heading is parsed at
  all, which is why an agent may name a prefix in prose while explaining what it
  did with someone else's handoff.
- **A blank line before the next heading.** That one is ordinary markdown and is
  what the skill's own example does. A blank line with another item after it is
  not, and is rejected.
- **A failed or cancelled run.** The check only runs when `status` is `success`.
  Exit 2 on a cancellation would refuse to let a cancelled subagent stop, which
  is the opposite of what a cancellation means. A failed run goes to Blocked and
  is not asked to reformat itself.

Blockers are extracted from the Decisions needed section only, not from the whole
message, and the validator rejects a typed line found under any other heading, so
a stray one under Done is caught by the validator instead of quietly parking a
false alarm in the human queue. Rescuing it silently would be worse than
refusing it: a misplaced blocker means the agent has the format wrong, and Alex
only learns that if the run is sent back.

### One rule set, two implementations

`evals/lib/handoff-check.sh` is the CI gate and applies the same rules to the
final assistant message of an eval run. The two are held identical by
`evals/lib/handoff-parity.sh`, which runs both over every case in
`evals/fixtures/handoff-cases/` and fails if a verdict ever differs:

```sh
evals/lib/handoff-parity.sh        # verdicts only
evals/lib/handoff-parity.sh -v     # and each side's reasons
```

Change one side and run it. They differ only in wording and in how many
complaints each lists for the same message; the verdict is the contract.

## The test gate

`TaskCompleted` has to decide whether tests pass, and nothing in the hook input
tells it. Resolved in this order:

1. **`CLAUDE_AGENTS_TEST_COMMAND`.** Run in `CLAUDE_PROJECT_DIR` (or the hook's
   `cwd`), wrapped in `timeout` if one is on the PATH. Exit 0 is a pass. The
   last 15 lines of output go on the Blocked item as a comment.
2. **A marker file**, `<project>/.claude/test-status`, overridable with
   `CLAUDE_AGENTS_TEST_STATUS_FILE`. First line `pass` or `fail`, the rest is
   detail that becomes the comment. Ignored if it is older than
   `CLAUDE_AGENTS_TEST_STATUS_MAX_AGE` (default one hour), so yesterday's green
   run cannot wave through today's work.
3. **Neither.** `CLAUDE_AGENTS_TEST_GATE=lenient`, the default, moves the item
   to Done and logs that the gate was not configured.
   `CLAUDE_AGENTS_TEST_GATE=strict` blocks completion instead.

Lenient is the default because a gate that refuses every task on a fresh install
is a gate nobody keeps. Set it to strict on the repos where the gate is the
point. Either way the board write happens before the exit, so blocking a
completion never costs the board its update.

## Per-agent tool scoping

`enforce-agent-scope.sh` switches on `agent_type` and denies with
`permissionDecision: "deny"`, quoting the invariant that was violated. Five
agents have rules; every other agent, and the main session, is untouched.

**`spec-writer`** - "Never write anywhere except under `docs/specs/`". Any
`Write`, `Edit`, `MultiEdit` or `NotebookEdit` whose path does not resolve inside
a `docs/specs/` directory is denied. Paths are made absolute against `cwd` and
normalised lexically first, so `docs/specs/../../etc/passwd` does not slip
through.

**`scout`** - "Never edit, write or create a file" and the Bash allowlist from
its Invariants. Write tools are denied outright. A Bash command is denied unless
every segment of it starts with `ls`, `cat`, `head`, `tail`, `sed`, `wc`,
`file`, `rg`, `grep`, `find`, `git`, `cd`, `pwd`, `echo` or `true`, with:

- `sed` requiring `-n` and rejecting `-i`, because the invariant says `sed -n`
- `find` rejecting `-exec`, `-execdir`, `-ok`, `-okdir`, `-delete` and the
  `-f*` actions, which run or write things
- `git` limited to `log`, `show`, `blame`, `diff` and `ls-files`
- redirection (`>`, `>>`), command substitution (`$(`, backticks) and process
  substitution denied anywhere in the command

`cd`, `pwd`, `echo` and `true` are on the allowlist and are **not** in scout's
Invariants. They are there because none of them can change state and all of them
turn up inside otherwise legal commands. That is the only addition; if you would
rather it were exactly the invariant, delete them from `SCOUT_ALLOWED_CMDS`.

Two deliberate softenings so the hook is not merely annoying: quoted spans are
stripped before the redirection scan, so `grep -rn '=>' src/` is allowed, and
`2>/dev/null` is removed before that scan, because discarding output is not a
state change.

**`fleet-steward`** - "Never touch anything outside the `claude-agents` working
copy" and "never run a git command that rewrites shared history". Write tools
are denied outside the repo root, and `git merge`, `rebase`, `reset`,
`filter-branch`, any force-push, `push --delete`, `push --mirror` and any push
naming `main` or `master` are denied. Pushing a feature branch and opening a
pull request are allowed, because that is the whole job.

The repo root is `CLAUDE_AGENTS_REPO` if set. Otherwise it is derived from the
plugin's own location: if the plugin sits at `<root>/claude-agents` and
`<root>/.claude-plugin/marketplace.json` exists, `<root>` is it. If neither
works, the check degrades to "the path contains a `claude-agents` directory" and
the deny message says to set `CLAUDE_AGENTS_REPO`.

**`reviewer`** - "Never edit, write or create a file", "Never run a git command
that writes ... Read-only git only" and "Never run tests, builds or installs".
Write tools are denied outright, which is the one that matters: section 4 of the
plan singles the reviewer out because a review agent that edits makes the diff
Alex approves a different diff from the one he read. `git` is an allowlist -
`log`, `show`, `blame`, `diff`, `ls-files`, `status`, `shortlog`, `describe`,
`rev-parse`, `rev-list`, `cat-file`, `grep`, `whatchanged` - because "read-only
git only" is wider than the seven verbs the invariant names and a denylist would
miss the eighth. Test runners, build tools and package managers are a denylist,
so the reviewer still reads the tree with `rg`, `cat` and `find`.

**`ui-designer`** - "Never run a git command that writes, and never install
anything into the product repo". The same read-only `git` allowlist. Installs are
matched on the verb rather than the command, because "use Bash only to build,
serve or screenshot a prototype" is the job: `npx serve` and `npm run build` are
allowed, `npm install`, `pnpm add`, `pip install`, `cargo add`, `go get` and
`brew install` are not. Write tools are left alone - `Write` is how a prototype
gets made, and `Edit` is already off its frontmatter.

This hook **fails open**. Bad input, a missing `jq`, an unexpected error: it logs
and allows. Be clear about what that costs. For the per-agent half there is no
second lock, because that is precisely the half `permissions.deny` cannot express:
a deny rule strong enough to stop `scout` writing stops `coder` writing too. The
session-wide half - credentials, `curl`, `sudo`, destructive git verbs - is denied
in `home/settings.json` and by the sandbox whatever this hook does. A
shell-command allowlist parsed with `sed` and `awk` is a speed bump for an agent
that has misread its brief, not a sandbox for one that is trying to get out.
`/sandbox` is the sandbox.

## Security

- The token is read from `~/.config/claude-agents/notion.token` (mode 600),
  rendered once by `scripts/install-home.sh`. **No hook ever calls `op`.** Plan
  section 12 is explicit: it adds latency to every subagent start and stop, and
  a locked `op` silently stops the board updating.
- The token never reaches a command line. `curl` is driven from a `--config`
  file written inside a 0700 temp directory and deleted immediately, so the
  Authorization header never appears in `ps` output. Passing it as `-H` would.
- Nothing echoes it. `lib/notion.sh` runs `set +x` on load, API error text is
  passed through a redaction filter before it is logged, and `NOTION_TOKEN` is
  cleared after each write.
- The token file's mode is checked and a warning logged if it is not 600 or 400.
- `board.env` is sourced, which is code execution. It lives in the same 0700
  directory as the token, which `permissions.deny` and the sandbox
  `denyRead`/`denyWrite` lists already keep away from every agent. If that
  directory is writable by something else, the token was gone first anyway.

## Failure behaviour

Every board write fails soft: log to stderr, exit 0. Notion being down, the
token being missing, `jq` not being installed, the page id being wrong - none of
it stops a session.

Exactly two things exit 2, and each for its own reason:

1. `SubagentStop`, when a successful run's handoff does not parse.
2. `TaskCompleted`, when the tests fail (or when the gate is strict and no
   result is available).

Neither exits 2 because Notion was unreachable. That separation is the point: a
board that cannot be written is an inconvenience, a coder marking itself done on
a red suite is not.

## Testing

The scripts read JSON on stdin and are ordinary shell, so drive them by hand.
`BOARD_DRY_RUN=1` keeps everything off the network, and pointing the config and
state directories somewhere disposable keeps it off your real board.

```sh
cd claude-agents/hooks
export CLAUDE_AGENTS_CONFIG_DIR=/tmp/ca/config
export CLAUDE_AGENTS_STATE_DIR=/tmp/ca/state
export BOARD_DRY_RUN=1
mkdir -p "$CLAUDE_AGENTS_CONFIG_DIR"
printf 'not-a-real-token\n' > "$CLAUDE_AGENTS_CONFIG_DIR/notion.token"
chmod 600 "$CLAUDE_AGENTS_CONFIG_DIR/notion.token"

# 1. spawn: binds the agent and moves the item to Doing
jq -n '{session_id:"s1",agent_id:"a1",agent_type:"coder",
        instructions:"Board-Item: 24f1a3b9c1d24e6f8a0b1c2d3e4f5061\nGo."}' \
  | ./board-subagent-start.sh

# 2. stop, with a blocker: Blocked by human, plus a comment
jq -n '{session_id:"s1",agent_id:"a1",agent_type:"coder",status:"success",
        last_assistant_message:"## Done\n- x\n\n## Not done\n- None\n\n## Unverified\n- None\n\n## Decisions needed\n- Blocker: 7 days or 30?\n"}' \
  | ./board-subagent-stop.sh; echo "exit $?"

# 2b. stop, clean success: no column moves, the "## Done" section is commented
jq -n '{session_id:"s1",agent_id:"a1",agent_type:"coder",status:"success",
        last_assistant_message:"## Done\n- Added rotation in src/api/auth.ts.\n\n## Not done\n- None\n\n## Unverified\n- None\n\n## Decisions needed\n- None\n"}' \
  | ./board-subagent-stop.sh; echo "exit $?"

# 3. stop, malformed handoff: exit 2 and the reasons on stderr
jq -n '{session_id:"s1",agent_id:"a1",agent_type:"coder",status:"success",
        last_assistant_message:"## Done\n- x\n\n## Decisions needed\n- maybe?\n"}' \
  | ./board-subagent-stop.sh; echo "exit $?"

# 3b. stop, a Blocker line in the wrong section: also exit 2, and the message
#     names the line and the section it turned up under
jq -n '{session_id:"s1",agent_id:"a1",agent_type:"coder",status:"success",
        last_assistant_message:"## Done\n- Blocker: 7 days or 30?\n\n## Not done\n- None\n\n## Unverified\n- None\n\n## Decisions needed\n- None\n"}' \
  | ./board-subagent-stop.sh; echo "exit $?"

# 4. the test gate, failing: Blocked, then exit 2
CLAUDE_AGENTS_TEST_COMMAND='exit 1' jq -n '{session_id:"s1",cwd:"/tmp",task_id:"t1",
        task_title:"Wire it [board:24f1a3b9c1d24e6f8a0b1c2d3e4f5061]"}' > /tmp/ca/in.json
CLAUDE_AGENTS_TEST_COMMAND='exit 1' ./board-task-completed.sh < /tmp/ca/in.json; echo "exit $?"

# 5. scoping: a deny prints JSON, an allow prints nothing
jq -n '{agent_type:"scout",tool_name:"Bash",cwd:"/tmp",tool_input:{command:"npm install"}}' \
  | ./enforce-agent-scope.sh | jq -r '.hookSpecificOutput.permissionDecisionReason'
```

Watch for the env-prefix trap in step 4: `VAR=x jq ... | ./hook.sh` sets the
variable for `jq`, not for the hook. Export it, or write the JSON to a file
first as above.

Expected exit codes: 0 everywhere except steps 3, 3b and 4, which are 2. Every
run appends to `$CLAUDE_AGENTS_STATE_DIR/log/hooks.log`.

For the format check specifically, `evals/lib/handoff-parity.sh` drives this same
script over a fixture set that covers valid handoffs, typed lines in each of the
three wrong sections, blank lines, missing and out-of-order headings, a stray H2,
untyped lines and trailing prose. It is faster than writing the JSON by hand and
it checks the CI gate at the same time.

To watch the real thing, run Claude Code with `--debug` - hook stderr goes to
the debug log - and `tail -f ~/.local/state/claude-agents/log/hooks.log`.

## What breaks them

- **`jq` or `curl` missing.** Both are checked and named in the log. The board
  stops updating; the session does not stop. macOS has `curl` but not `jq`.
- **The lead not emitting `Board-Item:`.** Everything runs, nothing moves. This
  is the most likely failure and the log line for it is explicit.
- **Column names that do not match.** Notion returns 400 and the log says so.
  Fix the names in `board.env`; do not rename the columns to match the code.
- **The integration not being shared with the page.** Notion returns 404 for a
  page the integration cannot see, which reads as "wrong page id" but usually is
  not. Share the Tasks database with the integration.
- **Renaming or moving a script** without updating `hooks.json`. The paths there
  are literal.
- **Dropping the execute bit.** `git update-index --chmod=+x` if it happens.
- **`set -x` anywhere in these scripts.** It would print the token. `lib/notion.sh`
  disables it on load; do not turn it back on.
- **Editing an agent's Invariants without editing `enforce-agent-scope.sh`.**
  The deny messages quote those invariants verbatim. If they drift apart, an
  agent gets told off for breaking a rule its body no longer states. The
  `migration-checklist` run is the place to catch that.

## Things the plan did not specify

Recorded here rather than discovered later. Every one of them is a decision this
layer had to make on its own:

1. **The `Board-Item:` spawn-prompt convention**, the `[board:<id>]` task-title
   marker, `CLAUDE_AGENTS_BOARD_PAGE_ID` and the state-file layout. The plan
   says the hook "is expected to know the item from the spawn context" and stops
   there.
2. **`board.env` and every default in it.** The plan never names the status
   property, its type, or how the column labels are spelled in Notion.
3. **How "tests pass" is decided**, the lenient default, the marker file and its
   staleness window. The plan asserts the gate and never says what it reads.
4. **A comment on the card at every transition**, and where each one's text
   comes from. The plan specifies a comment only for the `Blocker:` path. A card
   that says nothing but which column it is in is a status light, not a board.
   See "What the card says" above; the handoff format was not touched to get it.
5. **The `## Done` comment posted from `SubagentStop` rather than
   `TaskCompleted`.** The plan gives Done to `TaskCompleted`, which never
   receives a handoff, so the text is read where it exists and the column move
   is left where the plan put it.
6. **A successful run with no blockers changes no column.** The plan gives Done
   to `TaskCompleted`, so `SubagentStop` leaves the item in Doing. It comments
   there; it does not move it.
7. **The handoff check runs on success only**, and tolerates preamble prose,
   which is unparsed. Everything else in the skill is enforced strictly,
   including the blank-line rule and where a typed line may appear. See above
   for why.
8. **`cd`, `pwd`, `echo` and `true`** added to scout's Bash allowlist, and the
   quote-stripping and `2>/dev/null` softenings.
9. **`fleet-steward`'s repo-root resolution** by walking up from the plugin
   directory, and the git verb list, which is read off its Invariants prose.
10. **`Notion-Version: 2022-06-28`.** No version is named anywhere in the plan.
11. **The `SubagentStop` matcher.** The plan gives the hook to every subagent.
    Scoping it to the nine fleet agents is this layer's decision, made because
    the workflows spawn `Plan` and `general-purpose` lanes that return JSON.
12. **`reviewer` and `ui-designer` scoping rules**, including the read-only git
    allowlist both share and the install-verb matching that keeps
    `ui-designer` able to build and serve a prototype.
13. **The comment length cap.** `NOTION_COMMENT_MAX_CHARS`, its default of 8000
    and the `NOTION_COMMENT_HARD_MAX` clamp. Notion documents a per-object and a
    per-array limit but nothing specific to comments, so where to cut is this
    layer's choice; see "Comment length" above.
14. **Field-name defensiveness.** The brief for this work gives `SubagentStop` a
    `status` field of `success`, `failure` or `cancelled` and `TaskCompleted` a
    `task_title`. The published example blocks on
    `https://code.claude.com/docs/en/hooks` spell these `completion_reason`
    (`success`, `error`, `user_interrupt`) and `task_name`. Rather than pick
    one, the hooks read `.status // .completion_reason` and
    `.task_title // .task_name`, and normalise `error` to failure and
    `user_interrupt` to cancelled. **Confirm which is real against a live hook
    input and delete the loser**, because carrying both hides a rename.
