---
name: run-article
description: How to write a run article - the readable account of one run that the handoff cannot carry, covering what was tried and abandoned, what the constraint turned out to be, what surprised you and what to do differently. Articles live in the repo at docs/runs/, git-versioned beside the code they describe, and the path goes in a Done bullet so it reaches the board card. Preloaded into coder, reviewer, researcher and ui-designer, and used only when the spawn prompt asks for one; writable agents save under docs/runs/ and read-only agents return the article above their handoff.
when_to_use: Use when a spawn prompt asks for a run article, a write-up, a narrative account, an essay or a post-mortem of the work you are about to do or have just done, in those words or near them, and when the human asks for one after the fact. The ask comes from the lead at spawn time, so do not write one on your own judgement, and never write one instead of the handoff.
---

# Run article

The handoff is a receipt. It records what happened in lines a parser reads, and it says nothing about why: the two approaches you abandoned, the constraint that turned out to decide the design, what the code looks like now that it exists. That is the expensive part of a run and it is the part that evaporates when the transcript scrolls.

An article is that account, written down. One run, one article, and only when the spawn prompt asked for one.

## Who it is for

The next person who hits this problem, which is often you in three months with none of the context. Not a diary, not a status report, and not evidence that you were busy. Past tense, plain, specific.

The test for every paragraph: does it tell that reader something the diff and the handoff cannot? A list of completed steps is already in the handoff, and repeating it is waste that buries the paragraphs worth having.

## Shape and length

400 to 800 words. Under 400 it is a handoff with paragraphs. Over 800 nobody reads it, which costs exactly what writing nothing costs. Four sections, in this order, under a title and a one-line summary:

```
# <the work, as a phrase>

<one line: date, agent, issue or slug, and what the run did>

## What the run was
## What was tried and abandoned
## What the constraint turned out to be
## What to do differently
```

**What the run was** - two or three sentences of context, enough that a reader knows whether to keep going.

**What was tried and abandoned** - the dead ends, a short paragraph each, every one ending in why you stopped. Usually the longest section, and the reason the article exists: the reader is probably about to try one of them. An article that records only the path that worked is worth far less than one that names the three that did not. "Nothing was abandoned" is a suspicious claim about work substantial enough to have earned an article.

**What the constraint turned out to be** - the thing that actually decided it, which is often not the thing the brief said would decide it. Put what surprised you here, and what the code turned out to look like.

**What to do differently** - what you would do again, what you would not, and what the next person should check first.

Name real paths, real commands, real numbers. An article that could have been written without doing the work is not one. Nothing here is written in the human's voice; these are internal technical records by agents.

## Where it goes

`docs/runs/YYYY-MM-DD-<agent>-<issue-or-slug>.md`, in the repo the work happened in.

Date first, ISO, so the directory sorts chronologically and a reader can find the run they half remember by when it was. Agent second, because who wrote it says what kind of account to expect. Issue third - the same identifier `docs/specs/<issue>.md` and `docs/plans/<issue>.md` already use, so the three files line up under one grep; where there is no issue, a two to four word kebab slug naming the problem rather than the fix. A second article on the same day, agent and issue appends `-2`.

Commit it with the work. An article written in a `coder` worktree rides the same branch as the diff it describes, which is the whole point of putting it in the repo rather than in a state directory.

## If you write no files

`reviewer` and `researcher` never create a file - deliberately, by their frontmatter, and for `reviewer` by hook enforcement as well - and the article is not an exception worth carving. Return it as prose above your handoff instead, and say in a Done bullet that you did. The lead saves it to `docs/runs/` under the same convention.

One rule if you do that: no level-2 headings. A `## ` line anywhere in the final message fails the handoff check and your run is sent back to re-emit. Demote every heading one level; `### ` does not match the validator's `^## ` anchor. Prose above the handoff is tolerated on purpose, and this is what that tolerance is for.

## Naming it in the handoff

Put the path in a `## Done` bullet, on its own:

```
- Run article: docs/runs/2026-09-08-coder-EX-1-session-refresh.md
```

`SubagentStop` posts the `## Done` items as a comment on the board card, so the path reaches the card verbatim with nothing added to the handoff format and no hook changed. It only reaches the card on a clean run: a handoff carrying a `Blocker:` line gets the blocker comment instead, so the article is there for the next reader rather than for the person you are interrupting.

## Not an archive

An archive under `~/.local/state/claudecode-agents/archives/` is a verbatim copy of a card comment that was too long, written by a hook at the moment it cut one, on the human's machine only, unpruned and unbacked. It is a record, and it proves what was said.

An article is a piece of writing, by you, in the repo, versioned with the code, read in review like the code and deleted like the code. It explains what happened. Never paste a handoff into an article, never move an archive into `docs/runs/`, and do not treat one as a substitute for the other.

## Accumulation

`docs/runs/README.md` carries the convention and the pruning rule. Two things keep the directory readable and neither is an index anyone maintains: the date-first name sorts, and the one-line summary under every title makes `head -n 5 docs/runs/*.md` the index. Pruning is the same judgement `compound` applies to `.claude/rules/` on the quarterly pass - an article about code that no longer exists goes, because anything in it worth keeping was promoted into a rule, a skill or a memory long before.
