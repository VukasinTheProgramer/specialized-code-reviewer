// @ts-nocheck — this file's top-level `await`/`return` are valid only inside
// the Workflow tool's runtime (it wraps the script body in an async
// function); a standalone JS/TS checker flags them as errors outside one.
export const meta = {
  name: 'pr-review-verify',
  description: 'Scout maps the diff and hands ranked hypotheses to 4 slice verifiers, run in parallel and merged',
  phases: [{ title: 'Scout' }, { title: 'Verify' }],
}

// Everything git/bash (diff, manifest, scope, brief) is built by the caller
// before this runs — workflow scripts have no filesystem access. This script
// only orchestrates the agent fan-out: one scout, four Read/Grep/Glob verifiers,
// then a deterministic merge/sort. See .claude/skills/pr-review/SKILL.md.

const SCOUT_SCHEMA = {
  type: 'object',
  properties: {
    graph: { type: 'string', enum: ['on', 'off'] },
    context: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          kind: { type: 'string' },
          related: { type: 'array', items: { type: 'string' } },
          graph_coverage: { type: 'string', enum: ['hit', 'none'] },
        },
        required: ['file', 'kind', 'related', 'graph_coverage'],
      },
    },
    hypotheses: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          label: { type: 'string' },
          one_line: { type: 'string' },
          related: { type: 'array', items: { type: 'string' } },
          rank: { type: 'number' },
        },
        required: ['file', 'label', 'one_line', 'related', 'rank'],
      },
    },
    impacted: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          calls: { type: 'string' },
          graph_coverage: { type: 'string', enum: ['hit', 'none'] },
        },
        required: ['file', 'calls', 'graph_coverage'],
      },
    },
  },
  required: ['graph', 'context', 'hypotheses', 'impacted'],
}

const VERIFIER_SCHEMA = {
  type: 'object',
  properties: {
    slice: { type: 'array', items: { type: 'string' } },
    hypotheses_received: { type: 'number' },
    hypotheses_unread: { type: 'number' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          line: { type: 'number' },
          label: { type: 'string' },
          source: { type: 'string', enum: ['sweep', 'hypothesis'] },
          failure_mode: { type: 'string' },
          // minItems mirrors the low end of core/doctrine.md's bar ("two to
          // five ordered file:line steps") — evidence was previously not
          // required at all, so a finding could clear this schema with the
          // four other fields but no trace (explain-bug/SKILL.md already
          // defends against exactly that gap, confirming it was real).
          // No maxItems: doctrine states "two to five" as guidance on a
          // typical trace, not a hard ceiling — capping it would let one
          // finding needing a genuinely longer chain fail the whole slice's
          // structured-output call (coarser than the old per-finding drop
          // this schema is meant to tighten, not worsen).
          evidence: { type: 'array', items: { type: 'string' }, minItems: 2 },
        },
        required: ['file', 'line', 'label', 'failure_mode', 'evidence'],
      },
    },
    dropped_unreachable: { type: 'number' },
  },
  required: ['slice', 'hypotheses_received', 'hypotheses_unread', 'findings', 'dropped_unreachable'],
}

const SLICES = [
  { name: 'Access', agentType: 'pr-verify-access', labels: ['auth', 'ownership', 'security', 'data-exposure'] },
  { name: 'Data', agentType: 'pr-verify-data', labels: ['db', 'concurrency'] },
  { name: 'Answer', agentType: 'pr-verify-answer', labels: ['logic', 'validation', 'control-flow', 'state', 'contract'] },
  { name: 'Structure', agentType: 'pr-verify-structure', labels: ['duplication', 'dead-code', 'layering', 'a11y'] },
]

const LABEL_ORDER = {
  Access: ['auth', 'ownership', 'security', 'data-exposure'],
  Data: ['db', 'concurrency'],
  Answer: ['logic', 'validation', 'control-flow', 'state', 'contract'],
  Structure: ['layering', 'duplication', 'dead-code', 'a11y'],
}

const SLICE_ORDER = ['Access', 'Data', 'Answer', 'Structure']

const {
  outDir, repoRoot, base, head, scope, be, fe, graph,
  briefText, wiringFilesText,
  probesAccessText, probesDataText, probesAnswerText, probesStructureText,
  probesAllText, knownNonDefectsText, impactedCandidatesText,
} = args

const patchPath = `${outDir}/patch.diff`
const manifestPath = `${outDir}/manifest.txt`

// Pre-split by build-artifacts.sh so no verifier spawn has to open the
// domain pack itself to find its own rows — same content, delivered once.
const PROBES_TEXT = {
  Access: probesAccessText, Data: probesDataText,
  Answer: probesAnswerText, Structure: probesStructureText,
}

const labelToSlice = {}
for (const s of SLICES) for (const l of s.labels) labelToSlice[l] = s.name
// Labels a stack can't own: ownership/db need BE, state/a11y need FE.
const STACK_GATE = { ownership: 'be', db: 'be', state: 'fe', a11y: 'fe' }
// be/fe arrive from an LLM orchestrator following prose instructions (SKILL.md),
// not type-checked code — Number(...) coerces "1"/1/true alike so a stringified
// flag doesn't silently fail a strict === comparison (this exact bug shipped once).
const flags = { be: Number(be) === 1, fe: Number(fe) === 1 }

phase('Scout')
const graphSection = graph === 'on'
  ? `\ngraph: on — graphify MCP tools (get_node/get_neighbors/query_graph/shortest_path) are live; call them yourself per your agent definition.\n`
  : ''
// Pre-extracted by build-artifacts.sh so the scout doesn't Read the domain
// pack or the ledger itself — same content, delivered once, same reasoning
// as PROBES_TEXT above but the union (scout has no slice) instead of a split.
const domainPackProbes = probesAllText
  ? `\ndomain pack — this repo's own cited probes for every label (no need to\nopen the pack file yourself, this is already its whole '## Label probes'\ntable):\n\n${probesAllText}\n`
  : '\nNo domain pack this run — use the fallback Probes column in your own agent definition.\n'
const knownNonDefects = knownNonDefectsText
  ? `\nKnown non-defects — patterns a human has already ruled out here, each with\nthe guard that makes it safe (the ledger's own current text, no need to\nopen it yourself). Not a real hypothesis if it matches one of these:\n\n${knownNonDefectsText}\n`
  : ''
// Deterministic candidate list from build-artifacts.sh (§1.9) — unchanged files
// that reference something this diff changed, resolved by word-boundary grep at
// HEAD. Graph-independent on purpose: `impacted` used to be empty on every
// graph-off run, which is every repo without a graphify index. Candidates, not
// answers — the scout confirms each against the file and drops what doesn't hold.
const impactedCandidates = impactedCandidatesText
  ? `\nimpacted candidates — unchanged files that reference something this diff\nchanged, one \`caller<TAB>changed-file\` per line, already capped and with the\ndiff's own files removed. A reference is not a call: confirm each one before\nkeeping it, and drop the rest. With graph on, your own edge lookups take\nprecedence over this list where the two disagree.\n\n${impactedCandidatesText}\n`
  : '\nNo impacted candidates this run — nothing unchanged references the changed files, or the diff touches only files with no referencable name.\n'

const scoutPrompt = `graph: ${graph}

diff:      ${patchPath}
manifest:  ${manifestPath}
scope:     ${scope}

repository root: ${repoRoot}
Every path in your reply must be relative to that root.

${briefText}
${graphSection}
${domainPackProbes}
${knownNonDefects}${impactedCandidates}
Read the patch and the manifest, then emit context (every changed unit),
optionally up to 12 ranked hypotheses, and optionally up to 12 impacted
callers. See your own agent definition for the label table, the reading
rules and the exact contract for all three arrays.`

// A scout crash/timeout/schema-drift must not abort the whole run: every
// verifier's job 1 (its own sweep for its own labels) does not depend on the
// scout at all (SKILL.md §3.4), so degrade to "scout found nothing" instead
// of throwing — the run proceeds with no head start and no hypotheses,
// which costs coverage the scout would have added, never review that ran.
let scout
let scoutFailed = false
try {
  scout = await agent(scoutPrompt, {
    agentType: 'pr-review-scout',
    schema: SCOUT_SCHEMA,
    phase: 'Scout',
  })
} catch {
  scout = { graph, context: [], hypotheses: [], impacted: [] }
  scoutFailed = true
  log('Scout spawn failed — proceeding with no context, hypotheses or impacted callers; each verifier still runs its own job 1 sweep.')
}

let droppedHypotheses = 0
const bucket = { Access: [], Data: [], Answer: [], Structure: [] }
for (const h of scout.hypotheses || []) {
  const sliceName = labelToSlice[h.label]
  const gate = STACK_GATE[h.label]
  const stackOk = !gate || flags[gate]
  if (!sliceName || !stackOk) {
    droppedHypotheses++
    continue
  }
  bucket[sliceName].push(h)
}
for (const k of Object.keys(bucket)) bucket[k].sort((a, b) => a.rank - b.rank)

const contextText = JSON.stringify(scout.context || [])
const impactedText = JSON.stringify(scout.impacted || [])

function verifierPrompt(hyps, probesText) {
  const hypText = hyps.length
    ? hyps.map((h, i) => `  ${i + 1}. ${h.file} — ${h.label} — ${h.one_line}   rank ${h.rank}\n     related: ${(h.related || []).join(', ') || '(none)'}`).join('\n')
    : '(none — job 1 is the whole job)'
  const wiring = wiringFilesText
    ? `\nReadable without stating a reason, in addition to your standing free list:\n\n${wiringFilesText}\n`
    : ''
  const probes = probesText
    ? `\ndomain pack — this repo's own cited probes for your labels (use these before\nyour fallback prose; no need to open the pack file yourself, this is already\nevery row that applies to you):\n\n${probesText}\n`
    : '\nNo domain pack for your labels this run — use your own fallback prose.\n'
  return `Review this diff for your slice, then settle the hypotheses below.

Job 1 comes first and does not depend on the list: work the diff for your own
labels and raise anything that clears the five-field bar. Do not read the
hypotheses until job 1 is done — reading them first turns your review into a
search for more things like them.

Job 2: each hypothesis below is a guess from an agent that never opened the
file, handed to you ranked by how strongly it was suspected. Work them in
rank order and kill every one you cannot prove. If job 2 starts to crowd the
quality of what job 1 would have found, stop and report how many you left
unread — an unread hypothesis is cheaper than a thin sweep.

Killing a hypothesis is always silent — there is no third outcome and no
dismissal list. Either the code gives you a concrete triggering input or
state and a wrong outcome, and it is a finding, or you drop it and say
nothing.

It is still a finding when a nearby guard appears intended to prevent it, and
still a finding when nothing in the tree currently produces the triggering
state — "no caller passes that yet", "nothing sets that column False today",
"no route is wired to it yet" are reachability arguments, and reachability
never decides whether a defect is there. If you can state the trigger and the
wrong outcome, report it.

hypotheses:
${hypText}

context (from the scout, every changed unit in this diff — pick out what is
relevant to your own labels; the rest belongs to another slice):
${contextText}

impacted (from the scout, unchanged files that call into something this diff
changed — this diff's own lines don't cover them, so check whether the
change broke one of them under whichever of your own labels the breakage
would show up as; empty is normal, not a gap):
${impactedText}
${probes}
diff:      ${patchPath}
manifest:  ${manifestPath}

repository root: ${repoRoot}
Every path in the hypotheses and the diff is relative to that root. Reading
the same path under any other root gives you a different version of the file
and line numbers that do not match.

${briefText}
${wiring}`
}

// One spawn per slice. The merge below is written per-slice rather than per
// spawn, so it stays correct if a slice ever runs more than once again.
phase('Verify')
const verified = await parallel(
  SLICES.map((s) => () =>
    agent(verifierPrompt(bucket[s.name], PROBES_TEXT[s.name]), {
      agentType: s.agentType,
      schema: VERIFIER_SCHEMA,
      phase: 'Verify',
      label: `verify:${s.name}`,
    })
      .then((result) => ({ slice: s.name, result }))
      .catch(() => ({ slice: s.name, result: null }))
  )
)

const failed = []
const verifiedClean = []
const degraded = []
const sliceMismatch = []
let droppedMalformed = 0
let droppedUnreachable = 0
let unread = 0
const rows = []

const bySlice = {}
for (const s of SLICES) bySlice[s.name] = []
for (const v of verified) bySlice[v.slice].push(v.result)

for (const s of SLICES) {
  const slice = s.name
  const passResults = bySlice[slice].filter((r) => r && Array.isArray(r.findings))
  // Nothing parseable back for this slice — its labels went unreviewed.
  if (passResults.length === 0) {
    failed.push(slice)
    continue
  }

  for (const result of passResults) {
    unread += result.hypotheses_unread || 0
    droppedUnreachable += result.dropped_unreachable || 0
  }

  // A label is unreviewed if the slice's own echo didn't name it.
  const echoedUnion = new Set()
  for (const result of passResults) for (const l of result.slice || []) echoedUnion.add(l)
  const missingLabels = s.labels.filter((l) => !echoedUnion.has(l))
  if (missingLabels.length) sliceMismatch.push({ slice, missing: missingLabels })

  let kept = 0
  let returned = 0
  for (const result of passResults) {
    returned += result.findings.length
    for (const f of result.findings) {
      if (!f || !f.file || f.line == null || !f.label || !f.failure_mode || !Array.isArray(f.evidence) || f.evidence.length === 0) {
        droppedMalformed++
        continue
      }
      rows.push({ ...f, slice })
      kept++
    }
  }
  if (returned === 0) verifiedClean.push(slice)
  else if (kept === 0) degraded.push({ slice, returned })
}

// §5.3 — slice, then label in table order within slice, then file, then line.
function compareBySliceLabelFileLine(a, b) {
  const sa = SLICE_ORDER.indexOf(a.slice), sb = SLICE_ORDER.indexOf(b.slice)
  if (sa !== sb) return sa - sb
  const la = LABEL_ORDER[a.slice].indexOf(a.label), lb = LABEL_ORDER[b.slice].indexOf(b.label)
  if (la !== lb) return la - lb
  if (a.file !== b.file) return a.file < b.file ? -1 : 1
  return a.line - b.line
}

// Dedup key is file+line+label (§5.2) — first survivor wins, keeps its own evidence.
const seen = new Set()
const deduped = []
for (const r of rows) {
  const key = `${r.file}::${r.line}::${r.label}`
  if (seen.has(key)) continue
  seen.add(key)
  deduped.push(r)
}

// Tallied off the deduped set, not raw rows — a hypothesis-sourced duplicate
// that dedup collapses to one entry must not still count twice toward proven.
const proven = deduped.filter((r) => r.source === 'hypothesis').length

// A Set of matched sweep-finding keys, not a per-hypothesis counter — two
// hypotheses landing on the same file+label must not double-credit the one
// sweep finding underneath them (§5.3). Matching is by slice+file+label only
// — hypotheses carry no line (scout's {file, label, one_line, related, rank}
// shape has none) — so that's the finest disambiguation available; .find()
// skips any sweep finding already claimed by an earlier hypothesis in this
// same loop, so when two *distinct* sweep findings share a file+label (two
// different lines), two hypotheses on that file+label each claim a
// different one instead of both racing for the same first match while the
// second genuinely-distinct finding goes uncounted.
let alsoSwept = 0
const sweptMatched = new Set()
for (const s of SLICES) {
  for (const h of bucket[s.name]) {
    const match = deduped.find((r) => {
      if (!(r.slice === s.name && r.file === h.file && r.label === h.label && r.source === 'sweep')) return false
      const key = `${r.slice}::${r.file}::${r.line}::${r.label}`
      return !sweptMatched.has(key)
    })
    if (!match) continue
    const key = `${match.slice}::${match.file}::${match.line}::${match.label}`
    sweptMatched.add(key)
    alsoSwept++
  }
}

deduped.sort(compareBySliceLabelFileLine)

const findings = deduped.map((r, i) => ({
  n: i + 1,
  file: r.file,
  line: r.line,
  label: r.label,
  source: r.source || null,
  failure_mode: r.failure_mode,
  evidence: r.evidence || [],
}))

const scoutGraphCoverage = (scout.context || []).reduce((acc, c) => {
  acc[c.graph_coverage] = (acc[c.graph_coverage] || 0) + 1
  return acc
}, { hit: 0, none: 0 })

const hypothesesRaised = (scout.hypotheses || []).length
// What actually reached a verifier — raised minus what the router dropped
// (wrong label, wrong stack). Precision reads as proven ÷ routed, never
// ÷ raised, so a hypothesis nobody could act on doesn't count against it.
const hypothesesRouted = SLICES.reduce((acc, s) => acc + bucket[s.name].length, 0)

if (droppedHypotheses > 0) log(`${droppedHypotheses} scout hypothesis(es) dropped — label outside every slice, or outside this repo's stack scope`)
if (droppedMalformed > 0) log(`${droppedMalformed} finding(s) dropped — missing a required field`)
if (droppedUnreachable > 0) log(`${droppedUnreachable} candidate(s) dropped as unreachable — closing file not named`)
for (const d of degraded) log(`Degraded: ${d.slice} — ${d.returned} finding(s) returned, none renderable (missing fields). ${LABEL_ORDER[d.slice].join(', ')} was not reliably reviewed.`)
for (const m of sliceMismatch) log(`Warning: ${m.slice} echoed its slice without ${m.missing.join(', ')} — treat as unreviewed this run.`)

return {
  base,
  head,
  scope,
  graph,
  scout_failed: scoutFailed,
  slices_run: SLICE_ORDER,
  verified_clean: verifiedClean,
  failed,
  degraded,
  slice_mismatch: sliceMismatch,
  scout_graph_coverage: scoutGraphCoverage,
  hypotheses: { raised: hypothesesRaised, routed: hypothesesRouted, proven, also_swept: alsoSwept, unread, dropped: droppedHypotheses },
  dropped_malformed: droppedMalformed,
  dropped_unreachable: droppedUnreachable,
  findings,
}
