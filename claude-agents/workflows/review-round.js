export const meta = {
  name: 'review-round',
  description: 'Review a diff in numbered rounds: a cheap mechanical pass, then the Opus reviewer verdict, then fixes by coder, then re-review',
  whenToUse:
    'After a coder finishes a plan phase and before anything merges. One run does as many rounds as it takes, up to the cap.',
  phases: [
    { title: 'Scope the diff', detail: 'what changed, how much, and whether it touches anything sensitive' },
    { title: 'Round 1 mechanical', detail: 'lint, types, tests and obvious smells, in parallel', model: 'sonnet' },
    { title: 'Round 1 verdict', detail: 'the reviewer verdict and ranked findings' },
    { title: 'Round 1 fixes', detail: 'coder fixes the blocking findings; later rounds add their own groups' },
  ],
}

// ---------------------------------------------------------------------------
// review-round
//
// A round is one pass, and rounds are numbered - the glossary's definition, not
// a loose word for iteration. Each round is the plan's two-stage review:
//
//   1. A Sonnet mechanical pass, four lanes in parallel, leaning on the
//      pr-review-toolkit plugin for lint, types, tests and obvious smells.
//      Cheap, so the expensive stage never spends judgement on a lint error.
//   2. The Opus reviewer verdict. The reviewer never edits - that is its whole
//      value, because a reviewer that fixes things means the diff Alex approves
//      is not the diff he read.
//
// So fixes go back to coder, and the next round re-reviews the result. The loop
// ends when a round returns no blocking findings, or at the round cap, which is
// reported rather than passed off as a clean review.
//
// Escalation lives here rather than in the reviewer body, because the agent
// frontmatter is static and a diff touching authentication, authorisation,
// secrets or credentials earns a deeper look. That is the lead's policy, and
// this script is the lead writing it down.
//
//   /claude-agents:review-round { "base": "main", "head": "HEAD", "issue": "session-refresh" }
//   /claude-agents:review-round { "range": "main...feature/refresh", "maxRounds": 2 }
// ---------------------------------------------------------------------------

const SCOUT = 'scout'
const REVIEWER = 'reviewer'
const CODER = 'coder'

const SENSITIVE =
  /(auth|authz|authn|login|logout|session|token|jwt|oauth|saml|oidc|password|passkey|credential|secret|crypto|cipher|hash|permission|entitlement|\.env|keychain|vault)/i

const input = typeof args === 'string' ? { range: args } : args || {}
const range = input.range || (input.base && input.head ? input.base + '...' + input.head : 'HEAD~1...HEAD')
const issue = input.issue || null
const maxRounds = input.maxRounds || 3
const intentPath = issue ? 'docs/plans/' + issue + '.md' : input.plan || null

// --- Scope -----------------------------------------------------------------

phase('Scope the diff')
const scopeResult = await agent(
  [
    'Report on a diff and change nothing. Read-only git only.',
    'Run git diff --stat ' + range + ' and git diff --name-only ' + range + '.',
    'Return every changed path, the total lines added and removed, and the first line of each commit in the range.',
    'Do not review anything and do not offer an opinion.',
  ].join(' '),
  {
    agentType: SCOUT,
    label: 'scope ' + range,
    schema: {
      type: 'object',
      required: ['files', 'added', 'removed'],
      properties: {
        files: { type: 'array', items: { type: 'string' } },
        added: { type: 'number' },
        removed: { type: 'number' },
        commits: { type: 'array', items: { type: 'string' } },
      },
    },
  },
)

const scope = scopeResult || { files: [], added: 0, removed: 0, commits: [] }
if (!scope.files.length) {
  return {
    range,
    rounds: [],
    verdict: 'nothing to review',
    reason: 'The scope pass found no changed files in ' + range + '.',
  }
}

const sensitiveFiles = scope.files.filter((f) => SENSITIVE.test(f))
const sensitive = sensitiveFiles.length > 0
log(
  'Reviewing ' +
    range +
    ': ' +
    scope.files.length +
    ' files, +' +
    scope.added +
    '/-' +
    scope.removed +
    (sensitive ? '. Sensitive paths present, so the verdict runs deeper: ' + sensitiveFiles.join(', ') : '.'),
)

const LANES = [
  {
    name: 'lint and format',
    task: 'Run the repository lint and format checks over the changed files and report every violation the diff introduced. Use the pr-review-toolkit plugin checks where they cover this.',
  },
  {
    name: 'types and build',
    task: 'Run the type check and the build. Report every error the diff introduced, with file and line.',
  },
  {
    name: 'tests',
    task: 'Run the test suite, or the tests covering the changed files if the full suite is impractical. Report failures, and report any changed behaviour that no test covers. Say plainly which tests you actually ran.',
  },
  {
    name: 'obvious smells',
    task: 'Read the diff for the mechanical things a linter misses: dead code, a debug statement left in, a swallowed error, a copied block, a TODO shipped, a magic value, an unused import, a commented-out block. Report only what is mechanically checkable - leave judgement to the next stage.',
  },
]

const MECH_SCHEMA = {
  type: 'object',
  required: ['lane', 'ran', 'findings'],
  properties: {
    lane: { type: 'string' },
    ran: { type: 'array', items: { type: 'string' } },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'what'],
        properties: {
          file: { type: 'string' },
          line: { type: 'number' },
          what: { type: 'string' },
        },
      },
    },
    couldNotRun: { type: 'array', items: { type: 'string' } },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['verdict', 'summary', 'findings'],
  properties: {
    verdict: { type: 'string', enum: ['approve', 'approve with follow-ups', 'request changes'] },
    summary: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'what', 'why', 'blocking'],
        properties: {
          file: { type: 'string' },
          line: { type: 'number' },
          what: { type: 'string' },
          why: { type: 'string' },
          blocking: { type: 'boolean' },
        },
      },
    },
    unverified: { type: 'array', items: { type: 'string' } },
  },
}

// --- The rounds ------------------------------------------------------------

const rounds = []
let round = input.round || 1
let stopped = 'clean'

while (round <= maxRounds) {
  const tag = 'Round ' + round

  // A barrier is right here: the verdict stage needs every lane's findings in
  // hand, so that it can see what the mechanical pass already took.
  phase(tag + ' mechanical')
  const mechanical = (
    await parallel(
      LANES.map(
        (lane) => () =>
          agent(
            [
              'Mechanical review pass, ' + tag + ', over the diff ' + range + '.',
              lane.task,
              'Changed files:\n' + scope.files.join('\n'),
              'Report what you found and what you could not run. Do not fix anything and do not judge design.',
            ].join('\n\n'),
            {
              model: 'sonnet',
              effort: 'low',
              phase: tag + ' mechanical',
              label: tag + ': ' + lane.name,
              schema: MECH_SCHEMA,
            },
          ),
      ),
    )
  ).filter(Boolean)

  const mechCount = mechanical.reduce((n, m) => n + (m.findings || []).length, 0)
  if (mechanical.length < LANES.length) {
    log(tag + ': ' + (LANES.length - mechanical.length) + ' of ' + LANES.length + ' mechanical lanes returned nothing.')
  }
  log(tag + ': mechanical pass found ' + mechCount + ' items across ' + mechanical.length + ' lanes.')

  phase(tag + ' verdict')
  // No model override: the reviewer body already pins opus at high effort, and
  // the contract forbids conditional model logic in a body. Effort is raised
  // here only, because escalation is the lead's decision, not the agent's.
  const verdictOpts = {
    agentType: REVIEWER,
    phase: tag + ' verdict',
    label: tag + ' verdict',
    schema: VERDICT_SCHEMA,
  }
  if (sensitive) verdictOpts.effort = 'max'

  const review = await agent(
    [
      'Review the diff ' + range + '. This is ' + tag + '.',
      intentPath
        ? 'The change claims to implement ' + intentPath + '. Read it first: a change reviewed against no stated intent has not been reviewed.'
        : 'No plan or spec was supplied. Say so in your report and review against the code as it stands.',
      'The mechanical pass has already run, so the easy findings are taken. Spend your effort where only judgement helps.',
      'Mechanical findings already reported:\n' + JSON.stringify(mechanical, null, 2),
      sensitive
        ? 'This diff touches sensitive paths - ' +
          sensitiveFiles.join(', ') +
          ' - so spend your full budget on those files: authorisation on every path, secrets handling, session and token lifetime, and what an attacker gets from each one.'
        : 'No path in this diff looks security-sensitive, so review it as ordinary code.',
      round > 1
        ? 'This is a re-review. What the previous round asked for:\n' +
          JSON.stringify((rounds[rounds.length - 1].verdict || {}).findings || [], null, 2) +
          '\nSay for each of those whether it is now fixed, still open, or fixed in a way that introduces something new.'
        : '',
      'Give a one-sentence verdict, then the findings that justify it, worst first, each naming a file and a line, what breaks, and why that matters.',
      'Mark a finding blocking only when it must be fixed before merge. A reviewer who calls everything blocking gets ignored.',
      'Change nothing. Not a fix, not a test, not a note.',
    ]
      .filter(Boolean)
      .join('\n\n'),
    verdictOpts,
  )

  rounds.push({ round, mechanical, verdict: review })

  if (!review) {
    stopped = 'reviewer returned nothing'
    log(tag + ': the reviewer returned nothing. Stopping rather than treating silence as approval.')
    break
  }

  const blocking = (review.findings || []).filter((f) => f.blocking)
  log(tag + ': ' + review.verdict + ', ' + blocking.length + ' blocking of ' + (review.findings || []).length + '.')

  if (!blocking.length) {
    stopped = 'clean'
    break
  }
  if (round === maxRounds) {
    stopped = 'round cap'
    log(
      'Stopping at the round cap of ' +
        maxRounds +
        ' with ' +
        blocking.length +
        ' blocking findings still open. This is not an approval.',
    )
    break
  }

  // One coder, not one per finding. Parallel coders would each fix in their own
  // worktree and the fixes would not meet. Isolation is not set here either -
  // the coder body already carries isolation: worktree, and a fresh worktree
  // cut by this script could easily be cut from the wrong commit.
  phase(tag + ' fixes')
  const fixes = await agent(
    [
      'Fix the blocking findings from ' + tag + ' of the review of ' + range + '. Fix these and nothing else.',
      intentPath ? 'The plan this implements is at ' + intentPath + '.' : '',
      'Blocking findings:\n' + JSON.stringify(blocking, null, 2),
      'Non-blocking findings, for context only - do not fix them, they are follow-up work:\n' +
        JSON.stringify((review.findings || []).filter((f) => !f.blocking), null, 2),
      'A failing test first where the finding is a defect, then the smallest change that passes it. Commit small.',
      'If a finding is wrong, say so and leave the code alone rather than changing it to satisfy the review.',
      'Run the tests, the lint and the build before you finish, and record every command you could not run.',
    ]
      .filter(Boolean)
      .join('\n\n'),
    { agentType: CODER, phase: tag + ' fixes', label: tag + ' fixes' },
  )

  rounds[rounds.length - 1].fixes = fixes
  if (!fixes) {
    stopped = 'fix round returned nothing'
    log(tag + ': the fix round returned nothing. Stopping.')
    break
  }

  round += 1
}

const last = rounds[rounds.length - 1] || {}
const lastVerdict = last.verdict || {}
const stillBlocking = (lastVerdict.findings || []).filter((f) => f.blocking)

return {
  range,
  issue,
  intent: intentPath,
  sensitive,
  sensitiveFiles,
  roundsRun: rounds.length,
  stopped,
  verdict: lastVerdict.verdict || 'no verdict',
  summary: lastVerdict.summary || '',
  blocking: stillBlocking,
  followUps: (lastVerdict.findings || []).filter((f) => !f.blocking),
  unverified: lastVerdict.unverified || [],
  history: rounds.map((r) => ({
    round: r.round,
    mechanical: (r.mechanical || []).reduce((n, m) => n + (m.findings || []).length, 0),
    verdict: (r.verdict || {}).verdict || 'none',
    blocking: ((r.verdict || {}).findings || []).filter((f) => f.blocking).length,
    fixed: Boolean(r.fixes),
  })),
  nextStep:
    stopped === 'clean'
      ? 'No blocking findings. The follow-ups above are Propose item: lines for the lead to file, not merge blockers.'
      : 'Blocking findings remain after ' +
        rounds.length +
        ' rounds. Re-run with a higher maxRounds, or take the remaining findings to Alex as Blocker: lines.',
}
