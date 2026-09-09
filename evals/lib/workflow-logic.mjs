#!/usr/bin/env node
//
// workflow-logic.mjs - run the real workflow scripts with stubbed agents.
//
// The three workflow bugs the September 2026 review found were all in
// branching and aggregation, not in prompts: a claim promoted to verified by
// two agents failing to answer, a typo'd stage walking past the approval gate,
// and a fix round whose commits went somewhere the next round never looked.
// None of them needs a model to reproduce, and none of them would be caught by
// the handoff formatting suite.
//
// So the scripts are executed for real, with `agent`, `parallel`, `pipeline`,
// `phase` and `log` supplied as deterministic stubs. What this proves is the
// control flow. What it cannot prove is the native loader's behaviour -
// agentType resolution, skill loading, worktree base, the shape of a structured
// result - which stays a live integration check.
//
// Usage:  node evals/lib/workflow-logic.mjs [-v]

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const VERBOSE = process.argv.includes('-v')
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..')
const WORKFLOWS = join(ROOT, 'claude-agents', 'workflows')

let passed = 0
let failed = 0

function check(name, requirement, ok, detail) {
  if (ok) {
    passed += 1
    if (VERBOSE) console.log(`  ok    ${name.padEnd(34)} ${requirement}`)
  } else {
    failed += 1
    console.log(`  FAIL  ${name.padEnd(34)} ${requirement}`)
    if (detail !== undefined) console.log(`        got: ${JSON.stringify(detail)}`)
  }
}

// Run a workflow script with stubbed primitives. `respond` receives the prompt
// and the options and returns whatever that agent call should resolve to;
// returning null models a stopped or failed call, which is a documented result.
async function runWorkflow(file, args, respond) {
  const calls = []
  // new Function on file contents is the point of this harness, not an
  // oversight: the thing under test is the workflow script itself, and it uses
  // top-level `return`, so it only parses inside a function body the way the
  // real loader wraps it. The only string interpolated is a file read from this
  // repository's own claude-agents/workflows directory. Never point this at a
  // path that comes from anywhere else.
  const src = readFileSync(join(WORKFLOWS, file), 'utf8').replace(/^export const meta/m, 'const meta')
  const body = new Function(
    'agent',
    'parallel',
    'pipeline',
    'phase',
    'log',
    'args',
    `return (async () => {${src}})()`,
  )
  const agent = async (prompt, opts = {}) => {
    calls.push({ prompt, opts })
    return respond(prompt, opts, calls)
  }
  const parallel = async (fns) => Promise.all(fns.map((f) => (typeof f === 'function' ? f() : f)))
  // pipeline(items, stage, then) - `then` receives the first stage's result and
  // the original item, so an angle can carry its own name into stage two.
  const pipeline = async (items, stage, then) =>
    Promise.all(
      (items || []).map(async (item) => {
        const first = await stage(item)
        return then ? then(first, item) : first
      }),
    )
  const result = await body(agent, parallel, pipeline, () => {}, () => {}, args)
  return { result, calls }
}

console.log('\ndeep-research: a check that did not happen is not a vote in favour')

// Run the real cross-check with a fixed vote per lens. `null` models a stopped
// or failed agent call, which is a documented workflow result.
async function crossCheck(votes) {
  let i = 0
  let synthesis = ''
  const { result } = await runWorkflow('deep-research.js', { question: 'q', maxRounds: 1 }, (prompt, opts) => {
    const label = opts.label || ''
    if (label === 'frame') {
      return {
        restated: 'q',
        answerShape: 'shape',
        angles: [{ name: 'a', mode: 'web', looksFor: 'x' }],
        codebaseQuestions: [],
      }
    }
    if (/^(source quality|recency|contradiction):/.test(label)) {
      const v = votes[i]
      i += 1
      return v === null ? null : { verdict: v, why: 'reason-' + v }
    }
    if (/completeness critic/.test(prompt)) return { angles: [] }
    if (label === 'synthesis') {
      synthesis = prompt
      return 'report'
    }
    return { claims: [{ claim: 'c1', source: 's', why: 'w' }], deadEnds: [] }
  })
  return { counts: result.counts, unverified: result.unverified || [], synthesis }
}

// The review's table. Anything short of two clean positives is unverified, and
// a single refutation is never outvoted by silence.
for (const [votes, want, why] of [
  [['refuted', null, null], 'unverifiable', 'one refutation plus two missing checks'],
  [['stands', null, null], 'unverifiable', 'one positive is not enough on its own'],
  [['stands', 'stands', 'refuted'], 'unverifiable', 'a contradiction is not outvoted'],
  [['stands', 'stands', 'unverifiable'], 'stands', 'two clean positives and nothing against'],
  [['stands', 'stands', 'stands'], 'stands', 'all three lenses agree'],
  [['refuted', 'refuted', 'refuted'], 'refuted', 'all three lenses refute'],
]) {
  const { counts } = await crossCheck(votes)
  check(
    'votes-' + votes.map((v) => v || 'null').join('-'),
    why + ' -> ' + want,
    counts[want] === 1 && Object.values(counts).reduce((a, b) => a + b, 0) === 1,
    counts,
  )
}

// The reasons have to survive into the synthesis, or a contradiction that was
// found simply disappears from the record.
{
  const { synthesis } = await crossCheck(['refuted', null, null])
  check(
    'missing-lenses-recorded',
    'the synthesis is told how many lenses returned nothing',
    /returned no result/.test(synthesis),
    synthesis.slice(0, 160),
  )
  check(
    'refutation-reason-kept',
    "and the refuting lens's reason is carried forward",
    /reason-refuted/.test(synthesis),
    synthesis.slice(0, 160),
  )
}

console.log('\nspec-to-plan: an unknown stage never reaches the planner')

// R10. `plna` matched neither guard and fell through into plan generation,
// reporting itself afterwards as stage: 'plan'.
{
  let threw = null
  let spawned = 0
  try {
    await runWorkflow('spec-to-plan.js', { issue: 'example', stage: 'plna' }, () => {
      spawned += 1
      return { specExists: false, specApproved: false, planExists: false, evidence: 'none', related: [] }
    })
  } catch (e) {
    threw = e
  }
  check('invalid-stage-throws', 'an unknown stage is rejected', threw !== null, threw && threw.message)
  check('invalid-stage-spawns-nothing', 'and it is rejected before anything spawns', spawned === 0, spawned)
}

// The valid stages must still work, or the guard has just broken the workflow.
{
  const { result } = await runWorkflow('spec-to-plan.js', { issue: 'example', stage: 'plan' }, () => ({
    specExists: true,
    specApproved: false,
    planExists: false,
    evidence: 'status line reads draft',
    related: [],
  }))
  check('unapproved-plan-blocks', 'an explicit plan stage on an unapproved spec blocks', result.stage === 'blocked', result.stage)
}

console.log('\nreview-round: blocking findings come back as a handoff, not a silent re-review')

// R04. coder fixed in its own worktree and the next round re-read the original
// range. The run must now stop and say what the lead has to do.
{
  const { result, calls } = await runWorkflow(
    'review-round.js',
    { range: 'main...feature/refresh', maxRounds: 3 },
    (prompt, opts) => {
      if (/git diff --stat/.test(prompt)) return { files: ['src/a.ts'], added: 10, removed: 2, commits: ['c'] }
      if (opts.agentType === 'reviewer')
        return { verdict: 'changes requested', summary: 's', findings: [{ blocking: true, file: 'src/a.ts', what: 'bug' }] }
      return { findings: [] }
    },
  )
  check('fix-stops-the-run', 'a blocking verdict stops for a fix handoff', result.stopped === 'fix handoff required', result.stopped)
  const spawnedCoder = calls.some((c) => c.opts.agentType === 'coder')
  check('no-coder-spawned', 'and never commissions coder from inside the review', spawnedCoder === false, spawnedCoder)
  check(
    'fix-request-recorded',
    'the fix request names the range and the plan requirement',
    Boolean(result.history) && /new reviewed commit|fix commit|record the resulting/i.test(result.nextStep),
    result.nextStep,
  )
  check('range-reviewed-once', 'the same range is not reviewed twice in one run', result.roundsRun === 1, result.roundsRun)
}

// A clean verdict must still pass, or the workflow only knows how to stop.
{
  const { result } = await runWorkflow('review-round.js', { range: 'main...clean' }, (prompt, opts) => {
    if (/git diff --stat/.test(prompt)) return { files: ['src/a.ts'], added: 1, removed: 0, commits: ['c'] }
    if (opts.agentType === 'reviewer') return { verdict: 'approve', summary: 'fine', findings: [] }
    return { findings: [] }
  })
  check('clean-run-passes', 'a clean verdict still reports clean', result.stopped === 'clean', result.stopped)
}

console.log(`\n${passed} passed, ${failed} failed`)
if (failed) {
  console.log('A workflow branch approves the wrong thing, or has stopped doing its job.')
  process.exit(1)
}
console.log('The workflow branches decide on evidence, and still do the work they exist for.')
