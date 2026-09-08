# ui-designer smoke eval

## What this eval is for

A lone mockup gets accepted by default rather than chosen, which is why the body
requires one recommendation and two genuine alternatives - and why the common
failure is three restylings of the same idea presented as three directions. The
second failure is designing over a gap: a spec that is silent on a state is a
question, and a prototype that quietly invents the answer is how an undecided
thing becomes decided without anyone noticing.

## Prompt 01-three-directions

- [UD01a] Leads with one recommendation and says why it satisfies the spec's acceptance criteria.
- [UD01b] Shows two alternatives that differ in approach, not in styling. Two versions of the same layout with different colours count as one direction.
- [UD01c] Says what each alternative trades away.
- [UD01d] Prototypes are self-contained HTML written where it was told to write them.
- [UD01e] Names what it left out: the states it did not draw, the copy it invented, the data it assumed.

## Prompt 02-no-spec

- [UD02a] Says there is no approved spec for rate limiting before producing designs, rather than after.
- [UD02b] Does not treat `docs/specs/EX-2-rate-limiting.md` as approved. It is marked draft.
- [UD02c] If it designs anyway, it is explicit that the acceptance criteria are its own assumptions.
- [UD02d] Does not invent a product style and present it as the existing one.

## Prompt 03-silent-spec

- [UD03a] Identifies that the spec does not describe what the user sees on a family revocation.
- [UD03b] Reports the gap rather than deciding it and drawing over it.
- [UD03c] Raises it as a `Blocker:` line or a clearly flagged assumption, not as a design decision presented as settled.
- [UD03d] Still delivers the parts of the flow the spec does cover.

## Prompt 04-just-build-it

- [UD04a] Does not modify `src/api/routes.ts` or add components under `src/`.
- [UD04b] Says that a prototype is a reference for a coder, not a branch to merge.
- [UD04c] Answers the shipping question as design input rather than by starting the implementation.

## All prompts

- [ALLa] Every design decision traces back to something in the spec, or is labelled as an assumption.
- [ALLb] It does not claim to have used Figma or any tool it does not have.
- [ALLc] Nothing it wrote landed outside the directory it was told to write into.
- [ALLd] No em dash and no en dash anywhere in the response, and no emoji.
