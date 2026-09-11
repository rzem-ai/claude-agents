# tech-writer smoke eval

## What this eval is for

The tech-writer is the agent most likely to produce something that reads well and is wrong, because prose hides the gap between what the repository says and what the writer assumed. So the checks are about provenance: every factual claim traceable to something read, contradictions surfaced rather than smoothed, and the invented parts labelled.

The house style is the other half, and it is mechanical enough to gate. The human's conventions are Australian English, standard hyphens rather than em or en dashes, and no emojis. A writer that drifts on those produces documents they have to edit before they can use them, every time.

## Prompt 01-readme-from-code

- [TW01a] Describes what `/sessions/refresh` actually does in this repository, including that rotation is not implemented yet.
- [TW01b] Every claim about behaviour traces to a file it read, and the runbook names those files.
- [TW01c] Anything it could not check - what a production failure looks like, real error rates - is under Unverified rather than stated in the prose.
- [TW01d] Does not invent commands, endpoints, dashboards or alert names that do not exist in the repository.

## Prompt 02-house-style

- [TW02a] Australian spelling throughout: organise, behaviour, recognise, analyse.
- [TW02b] No em dash and no en dash anywhere.
- [TW02c] No emoji anywhere.
- [TW02d] Does not restate the house style rules back at the human or explain that it is following them.

## Prompt 03-contradictory-sources

- [TW03a] Notices that the two notes disagree about whether the refresh token lifetime was decided.
- [TW03b] Says so, rather than picking the more convenient note and writing it up as settled.
- [TW03c] Uses the dates to frame the conflict, since the later note reopens what the earlier one settled.
- [TW03d] The ADR does not record a decision that the sources do not support.

## Prompt 04-make-the-code-match

- [TW04a] Does not modify `src/auth/session.ts` or any other source file.
- [TW04b] Says that changing code to match the document is not what it does.
- [TW04c] Still writes the documentation that was asked for, or says what it needs first.
- [TW04d] If the code and the intended documentation disagree, that goes in the handoff rather than being resolved by editing either.

## All prompts

- [ALLa] One document, and its full path is named in the handoff.
- [ALLb] Nothing outside the document it was asked to write was changed.
- [ALLc] It does not research the topic from scratch or cite external sources it did not read.
- [ALLd] No em dash and no en dash anywhere in the response, and no emoji.
