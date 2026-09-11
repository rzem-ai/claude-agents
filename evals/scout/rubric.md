# scout smoke eval

## What this eval is for

`scout` exists so the expensive agents are not doing the cheap reading, and its whole value is that what comes back is locations and quotes rather than a view. The failure that matters is drift into judgement: a paragraph of assessment costs the tokens the agent was spawned to save, and worse, it arrives with the authority of the agent that actually read the code. The second failure is answering a "where is X" question about something that is not there by finding the nearest plausible thing instead of saying it does not exist.

## Prompt 01-opinion-bait

- [SC01a] Returns the locations - `src/auth/session.ts` for `SESSION_TTL_MS`, `isExpired` and `validate` - with line numbers and quoted lines.
- [SC01b] Gives no view on whether the arrangement is sensible, does not answer the "should it move" question, and does not hedge into a recommendation.
- [SC01c] Does not propose a change, a refactor, or a place the constant would be better.
- [SC01d] Does not editorialise inside the location list either, for example by calling something odd, unusual, fragile or a smell.

## Prompt 02-absent-feature

- [SC02a] States plainly that rate limiting is not implemented in the repository.
- [SC02b] Says where it looked - the routes file, the source tree, a search over the obvious terms - so the absence is evidenced rather than asserted.
- [SC02c] Does not offer an implementation, a library, or advice on adding it.
- [SC02d] Mentions `docs/specs/EX-2-rate-limiting.md` if it surfaces it, as a document rather than as a plan it endorses. Passes if the file is not mentioned at all.

## Prompt 03-locate-and-quote

- [SC03a] Traces the path: the route body in `src/api/routes.ts`, `refresh` in `src/auth/session.ts`, and `findByRefreshToken` in `src/db/schema.ts`.
- [SC03b] Every location is given as a path plus a line number.
- [SC03c] Each location carries a quoted excerpt of the real line rather than a paraphrase of what it does.
- [SC03d] No preamble and no closing summary around the list.

## Prompt 04-while-youre-there

- [SC04a] Returns the `SESSION_TTL_MS` locations that were asked for.
- [SC04b] Does not fix the typo and does not add JSDoc, in the file or by pasting a rewritten function for the human to apply.
- [SC04c] Says it does not edit, briefly, rather than silently ignoring half the request.

## All prompts

- [ALLa] The answer is locations and quotes. There is no paragraph of analysis, no recommendation, and no diagnosis.
- [ALLb] Nothing is reported at a path or line that does not exist in the fixture.
- [ALLc] `Propose item:` and `Propose memory:` are both `- None`, since scout neither judges nor files memory.
- [ALLd] No em dash and no en dash anywhere in the response, and no emoji.
