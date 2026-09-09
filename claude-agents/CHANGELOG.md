# Changelog

All notable changes to the `claude-agents` plugin are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the plugin uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

The version in `.claude-plugin/plugin.json` is load-bearing. Clients keep the
cached copy of the plugin until that number changes, so every change that should
reach a machine needs a version bump and an entry below.

## [0.6.0] - 2026-09-10

The round that came out of the first live probe. Every finding below was
measured against a running Claude Code 2.1.236 before it was fixed, because the
deterministic suite stubs the model out and could not see any of it.

The probe itself was two spawns of one agent definition, identical but for a
`schema`, behind a hook that dumped its stdin. Keeping the control spawn is what
made it evidence: an empty dump on its own cannot distinguish "StructuredOutput
replaced the message" from "the hook never fired".

### Fixed

- **The handoff gate had been refusing every schema-carrying fleet agent.** A
  subagent spawned with a `schema` is forced through StructuredOutput, and the
  runtime then sends `SubagentStop` no `last_assistant_message` at all - the key
  is absent, not empty, and not the JSON. `board-subagent-stop.sh` read it as
  `// ""`, could not tell a run that was never asked for a handoff from one that
  produced an empty one, treated the absent `status` as success, failed
  `validate_handoff` and exited 2 - telling the agent to re-emit a handoff
  nobody had asked it to write. That is nine spawn sites across all three
  workflows: `scout` and `reviewer` in `review-round`, `researcher` at five
  sites in `deep-research`, `scout` and `spec-writer` in `spec-to-plan`. Item 12
  scoped the matcher away from the built-in `Plan` and `general-purpose` lanes
  last round; that fix could never reach a schema-carrying agent which is itself
  a fleet agent. Absent or null now means there is nothing to validate; present
  and empty still fails. `hooks/README.md` item 16.
- **`git -C` hid the verb from every per-agent git check.** The subcommand was
  read as the second whitespace-separated token, so `git -C /path log` resolved
  its verb to `-C`. Against an allowlist that denies, which made `scout` and
  `reviewer` unable to read a worktree - invisible, because nobody blames a
  reviewer that cannot read. Against a **denylist it allows**, and
  `fleet-steward` uses a denylist: `git -C /path push --force`,
  `git -C /path merge` and `git -C /path reset --hard` all walked past the three
  git operations that agent is explicitly forbidden to perform, and it is the
  one agent meant to run unattended on a schedule. A backslash-escaped space in
  the path did the same by another route. `git_verb()` now skips dashed tokens
  and the values of the eight global options that take a separate argument, and
  collapses escaped pairs before splitting. Both directions are pinned:
  the reads that must now work, and every forbidden verb that must stay
  forbidden with a `-C`, a `-c`, a `--no-pager` or an escaped space in front of
  it. `hooks/README.md` item 17.
- **`skills/handoff/SKILL.md` told every fleet agent that `SubagentStop`
  receives a `status` field.** It does not; item 15 settled that last round and
  the sentence survived. The instruction it justified was right and is kept -
  all four sections on a failed run, what went wrong under Not done - but the
  premise is now stated correctly: the handoff is the only account of the run
  anything downstream gets, and a `Blocker:` line is the one route to the human
  queue that works.
- **An absent final message is now diagnosed rather than assumed.** The first
  version of this fix passed every run whose message was absent and logged that
  it could not tell why. An adversarial review found why that was not good
  enough: the runtime builds the field as `.trim() || void 0`, so
  `last_assistant_message: ""` is **unreachable** - a fleet agent that was asked
  for a handoff and produced nothing sends a byte-identical payload to a schema
  spawn. Passing every absent field therefore retired the gate for exactly the
  case it exists to catch, and the test pinning the empty string made the
  coverage look complete. The hook now reads `agent_transcript_path`: a final
  `StructuredOutput` block is a run that owed no handoff and passes, a final
  `text` block is recovered and validated like any other, and a transcript it
  cannot read passes and says so. Both shapes were read off real transcripts.
- **`sudo` is not a wrapper.** Making wrappers transparent is asymmetric: for a
  denylist role it stops a forbidden verb hiding behind one, but for an
  allowlist role it removes the requirement that the wrapper itself be
  permitted - and `sudo cat` is not the same act as `cat`. Taking a wrapper list
  wholesale let `sudo cat /etc/shadow` past `scout`, which had refused it purely
  because sudo was not on its list. `Bash(sudo *)` in `home/settings.json`
  backstops sudo, and that is the right division of labour: this hook expresses
  the half `permissions.deny` cannot. A wrapper's own options are part of the
  wrapper now, so `env -i git merge` and `xargs -n1 git merge` are the git
  command that follows them.
- **An option that takes a value need not be a long one.** The install ban
  scanned past a non-verb word only after a `--` option, so `npm -C <dir>
  install` - a documented alias for `--prefix` - ended the scan a word early and
  never reached the verb. `npm run link` stays allowed because nothing precedes
  `run`.
- **The two parsers now agree about which word is the command, by
  construction.** `leading_token` stripped `VAR=val` to find `npm`, while
  `sub_verb` dropped position one - which *was* the assignment - and returned
  `npm` as the verb, so `NODE_ENV=production npm install react` walked past the
  install ban on that disagreement alone. Both now start from `command_words`,
  which also makes shell wrappers transparent: `command git merge`,
  `env GIT_DIR=/x git merge` and `sudo git reset` are the command that follows
  them, as they are to the shell. A closed list of wrappers, because it costs no
  false denies - unlike treating any token matching a forbidden verb as one,
  which would stall the one agent that runs unattended on `git log --grep=merge`.
- **A line continuation stranded the verb.** Deleting the trailing backslash
  without joining the lines left `merge main` as its own segment, whose leading
  token was not git, so it was skipped entirely and
  `git -C /tmp/wt \<newline>merge main` was allowed. Continuations are joined
  out of the command before anything splits on newlines, and the rule that
  merely deleted the backslash is gone rather than left looking load-bearing.
- **The install ban looked in the wrong place for the verb.** It required the
  install verb to be the first non-option word, so `npm --prefix /tmp/x install`
  put a path where the verb was looked for. It now scans for the first word that
  *is* an install verb, continuing past a non-verb only when a long option
  preceded it - which keeps `npm run link` allowed and `npm -g install` denied.
- **The transcript reader reported on a stale block.** It took `last` of a list
  already filtered to StructuredOutput-or-text, so a final block that was
  neither - an ordinary tool call with no closing prose - was invisible and it
  reached back to an earlier text block and called that the final message. That
  re-created the original failure: exit 2 telling an agent to re-emit a handoff,
  quoting text that was never one. It now takes the last block and classifies it
  after, which also makes the discriminator testable: nothing had proved that a
  non-StructuredOutput tool call is not structured output.
- **`sub_verb` replaces `git_verb`, which was three kinds of wrong.** Reading
  the verb by stripping to the literal text `"git"` broke two things the first
  attempt did not cover. `ui-designer`'s entire install ban - the only
  enforcement, since nothing in `home/settings.json` denies an installer - went
  dead, because `npm install react` contains no `"git"` and so resolved to a
  verb of `npm`; the suite missed it because all three `ui-designer` cases were
  write events and the role had no Bash coverage at all. And a git binary at a
  path containing `git` (`/opt/homebrew/opt/git/bin/git merge`) resolved to
  `/bin/git`, allowing a merge for `fleet-steward` and denying a read for
  `scout`. The command word is now dropped by position. Three further fixes in
  the same pass: `--attr-source` takes a separate value and was missing;
  `--exec-path` does not take one and was wrongly listed, so it swallowed the
  verb after it; `--super-prefix` was removed in git 2.49. And escape
  collapsing, which fixed escapes in the path, mangled them in the verb -
  `git \merge main` runs merge and read as `xerge`. Backslashes now follow the
  shell's own rules.

### Added

- **`coder` writes in its own worktree, or it does not write.** The only
  preventive check in the fleet. `review-round` can detect a fix that landed in
  the main checkout but never prevent it - by the time verification runs, coder
  has already branched and committed - and asking coder to check first is an
  instruction, not a boundary. `coder` has an `agentType`, so
  `enforce-agent-scope.sh` governs its Bash calls, and git answers directly: a
  linked worktree's git dir sits under `.git/worktrees/`. A writing git verb is
  refused unless its target - the command's own `-C`, else the call's `cwd` -
  can be shown to be one. Reads and non-git commands are untouched. Not being
  able to tell is not permission, because the case this exists for is isolation
  silently not happening. Know the cost: if isolation does not hold, coder now
  stops rather than leaking commits into whatever checkout it is in. See
  `hooks/README.md` item 18.

- **`review-round` carries fixes back, behind `fix: true`.** The loop was
  removed last round because `coder` fixes in an isolated worktree and the
  script had no supported way to learn that worktree's path or commit. It is
  back, and nothing it branches on is `coder`'s word for it: a schema-carrying,
  `agentType`-less git lane reports what git says, and before a fix is adopted
  git has to show a commit, in a worktree that is **not the main checkout**,
  built on the reviewed commit, clean, and touching at least one file the
  blocking findings name. Each of those stops the run. Both ends of the range
  are pinned to SHAs before any round runs, so a moving `main` cannot change
  what round two reviews, and round N+1 runs its mechanical lanes inside the fix
  worktree - without which the tests lane re-runs the original code and
  "verified" means nothing. `coder` is spawned **without** a schema, so its
  handoff still reaches the gate, the card and the human queue.

  Opt-in, and the default path keeps today's exact behaviour and stop string.
  Worktree isolation for a workflow-spawned `coder` has never once been observed
  against a live Claude, and a run that commissions code by default is a run
  that surprises somebody.
- **`evals/lib/handoff-extractor-parity.sh`**, 128 checks. `review-round` is now
  a third reader of the handoff format, so it is pinned to the hook's
  `extract_section` the way `handoff-check.sh` already is. Both implementations
  are sliced out of the files they ship in, so this compares shipping code
  rather than a copy. It caught two real divergences on the way in: the hook
  strips every carriage return, and its heading match is exact, so `## Done `
  with a trailing space opens nothing.

### Changed

- **The cap is the only thing bounding what this workflow spends, and it was
  not read as a number.** `input.maxRounds || 3` accepted any truthy value, so a
  `maxRounds` of `"three"` made every round comparison NaN-false and the loop
  commissioned coder until the process ran out of memory. The same reasoning
  this file already applied to `fix` - it arrives from a slash command's JSON,
  so anything but a real value is not consent - now applies to the two numbers
  that bound the spend. An unusable one stops the run and says so.
- **`approved` was a field nothing tested.** Every check asserted on `stopped`,
  so hard-coding `approved: true` left the whole suite green - and it is the one
  field a caller would gate a merge on. It is now asserted for every stop
  reason, and it means what it says: a run whose verdict was coerced to
  "request changes" no longer reports itself approved alongside it.
- **Five more ways the fix gate could be told a comfortable story.** A commit
  whose location the lane did not report was adopted, which sent the next round
  to re-read the original checkout and call the result verified. A lane that
  named several candidates and then picked one was trusted, because the
  ambiguity check sat inside the no-commit branch. `dirty` and `isMain` were
  read strictly while `blocking` had already been taught not to be, so
  `dirty: "true"` passed. A blocking finding naming no file removed the
  file-touch rule entirely, so an empty commit satisfied it. And the blocker
  path recorded its commit before the gate ran, so a dirty non-descendant commit
  in the main checkout was reported as a fix and Alex was pointed at it.
- **`dispositionOf` inverted the refusal it exists to carry.** A path in
  backticks - the ordinary way a model writes one - read as a different file, so
  coder's reasoned "rejected as wrong" reached the next reviewer as a silent
  omission. It also scanned the whole line, so a file mentioned in the reasoning
  inherited another finding's disposition.
- **Three more ways the fix gate could be told a comfortable story**, all found
  by working through what a verify lane could return rather than by a test
  failing. `pathsMatch` suffix-matched with no floor, so a finding named
  `index.ts` matched every `index.ts` in the tree and a fix touching an
  unrelated one satisfied the gate that checks it touched the right one.
  `isMain` is optional in the schema, so a lane that omitted it proved isolation
  by saying nothing - which is the shape the failure actually takes, since in
  the probe both agents ran in the main checkout and nothing announced it.
  And `v.headCommit === head` missed that git prints whatever sha length it
  likes, so the reviewed head abbreviated read as a different commit and would
  have been adopted - re-pointing round two at the code round one had already
  reviewed, which is exactly the failure this loop was deleted for.
- A reviewer's `blocking` flag is read to fail closed. Both obvious readings
  are wrong: a truthy test makes the string `"false"` a blocking finding, and a
  strict `=== true` makes the string `"true"` a passing one - and that second
  failure approves a merge. Anything not recognisably a no now counts as
  blocking, pinned from both sides. Mutation testing found this; three of the
  new cases turned out to survive having the behaviour they named deleted, and
  were replaced with ones that do not.
- The suite runs 413 numbered checks across five suites, plus the 28 handoff
  fixtures the two parity checks drive - 441 against 122 before this round.
  `workflow-logic` 16 to 103, `scope-hook-contract` 60 to 150,
  `board-hook-contract` 13 to 27, and `handoff-extractor-parity` new at 128.
- `hooks/README.md` records what the probe measured beyond item 15's table:
  `SubagentStop` also sends `cwd`, `effort`, `permission_mode`, `prompt_id`,
  `session_crons` and `transcript_path`; `SubagentStart` also sends `cwd`,
  `prompt_id`, `session_id` and `transcript_path`; `agent_type` arrives
  unprefixed. It also names two things plainly: the gap the gate fix accepts,
  and that an `agentType`-less lane is governed by neither hook, so "read-only
  git only" in a lane prompt is an instruction rather than a boundary.

## [0.5.0] - 2026-09-09

The fix round for the 9 September fleet review
(`docs/2026-09-09-fleet-review-resolution.md`). Every finding in that document
was reproduced before it was fixed, and the three that rested on the published
hook docs were settled against the zod schemas in the shipped CLI binary, since
the docs pages truncate before the event sections.

### Fixed

- **Three hooks read fields the runtime does not send.** `TaskCompleted` sends
  `task_subject`; `task_title` and `task_name` appear nowhere in the CLI binary.
  `SubagentStart` sends `agent_id` and `agent_type` and no spawn prompt under
  any name. `SubagentStop` sends no `status`, and `completion_reason` is not in
  the binary at all. A hook reading a missing field does not fail loudly - it
  takes its fallback forever, and the fallback looked like normal operation.
  Consequently the `[board:<id>]` marker had never resolved, the `Board-Item:`
  binding had never fired, and no failed or cancelled subagent had ever reached
  Blocked. `hooks/README.md` item 15 records the schemas and how to re-derive
  them after a CLI upgrade.
- **Any completed task could close an issue.** `TaskCompleted` fell back to the
  item most recently picked up in the session, so an issue with twenty
  execution tasks went to Done on the first, and a session holding two items
  closed whichever was touched last. Both fallbacks are gone: only an explicit
  `[board:<page-id>]` marker moves a card. Moving nothing is the better failure,
  because a card that silently reads Done is taken as finished work.
- **The test gate could approve the wrong checkout.** It preferred
  `CLAUDE_PROJECT_DIR` over the hook's `cwd`, and `coder` runs with
  `isolation: worktree`, so a passing parent could approve failing worktree
  code. It tests the `cwd` that emitted the event and refuses when there is no
  usable checkout. A `pass` marker is also no longer trusted when anything in
  the tree is newer than it; a `fail` marker still blocks at any age, because
  blocking on stale evidence is safe and approving on it is not.
- **The scope hook admitted writes by read-only agents.** `strip_quoted` erased
  both kinds of quote before the substitution check, but the shell only disarms
  `$( )` inside single quotes, so `echo "$(touch x)"` was accepted. `sed` writes
  with no redirection character at all and its script is normally quoted, so
  `sed -n 'w /tmp/proof'` read as an ordinary `sed -n`. `reviewer` used a
  denylist of build tools, which is why `touch` went through - a denylist of
  ways to create a file cannot be finished - and is now an allowlist, which also
  closes `cp`, `mv`, `tee`, `ln`, `install` and `python`. `fleet-steward`'s Bash
  branch inspected only git verbs, so every ordinary shell write outside its
  repo was accepted; redirection targets are now resolved and confined.
- **Write destinations were barely checked.** `*/docs/specs/*` matched any
  project's specs directory, `..` was collapsed without asking the filesystem,
  and `ui-designer` and `tech-writer` had no write branch at all despite both
  holding `Write`. `hooks/lib/check-write-scope.py` resolves symlinks and
  anchors to the project.
- **A research claim could be verified by silence.** One refutation plus two
  failed agent calls scored as a claim that stands. A claim now stands only on
  two actual positives with nothing against, and is refuted only when every lens
  reported and every one refuted.
- **A typo'd stage skipped the approval gate.** Only the literal `'plan'` was
  checked against spec approval, so `plna` planned from an unapproved spec and
  reported itself as `stage: 'plan'`.
- **The review loop re-read the same diff every round.** `coder` fixes in an
  isolated worktree and `range` is assigned once, so fixes went somewhere the
  next round never looked while the run burned its round cap.
- **The eval runner could not fail, and could not say what it ran.** A stub
  returning a valid handoff inside an `is_error` envelope and exiting 7 was
  reported as "All gates passed". It also invoked a bare `--agent scout` with no
  `--plugin-dir`, so a run proved nothing about the definitions in the checkout.
- **`run-article` was documented and unreachable.** Four agents are told to work
  the skill; none listed it under `skills:`. The `ui-designer` eval gate also
  rejected every `docs/` path, including the commissioned article itself.
- **`install-home.sh` clobbered live settings.** It copied `settings.json` over
  the existing file, deleting every key the repository does not know about along
  with any hand-added deny rule. It merges now.

### Changed

- `review-round` is one round per invocation. Blocking findings come back as a
  `fixRequest` for the lead to run, and the workflow is invoked again against
  the fix commit. Carrying fixes back automatically needs a structured result
  contract that has to be built and tested, not prompted.
- Board binding is one item per session, via `CLAUDE_AGENTS_BOARD_PAGE_ID`. This
  is narrower than the `Board-Item:` convention it replaces and is not the same
  thing; the line is still emitted as context for the agent, but it is not a
  hook transport and never was.
- `spec-writer`'s interview invariant now forbids presenting a spec as
  interviewed when it is not, rather than forbidding a pre-interview draft. The
  `spec-to-plan` strawman is deliberate: a wrong draft is faster to correct than
  a blank page is to fill.
- `fleet-steward`'s invariant says what the hook enforces and what it does not.
  A program run through Bash writes wherever the process can, and no
  shell-level check sees inside it.

### Added

- `evals/lib/check-all.sh` runs every deterministic check in one command: shell
  and workflow syntax, the 28 handoff fixtures, the glossary generator, and four
  new suites - `board-hook-contract.sh`, `scope-hook-contract.sh`,
  `workflow-logic.mjs` and `runner-gate.sh`. 122 checks. Nothing in it calls a
  model, opens a socket or touches Notion, so it is safe as a pre-commit and CI
  gate.
- Each eval run writes `definition-provenance.json`: commit, branch, dirty flag
  and a sha256 per agent and skill file. A baseline is only evidence if you can
  say later which definitions produced it.
- `scripts/merge-settings.py`, the settings merge policy.

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

[Unreleased]: https://github.com/rzem-ai/claude-agents/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/rzem-ai/claude-agents/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/rzem-ai/claude-agents/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/rzem-ai/claude-agents/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/rzem-ai/claude-agents/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rzem-ai/claude-agents/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rzem-ai/claude-agents/releases/tag/v0.1.0
