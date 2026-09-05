# Pipeline internals — what the Workflow script does

Read when interpreting a `pr-review-verify` result, tuning the scout/verifier split, or changing
`.claude/workflows/pr-review-verify.js`. Not needed to run a review — `SKILL.md` Step 3 makes one
call and Step 5.4 persists what comes back.

Section numbers match `SKILL.md` and the rationale.

`SKILL.md` Step 3 makes the single Workflow call and builds its payload from `run.env`; this file is what happens after that call is made.

One cheap scout pass maps the whole diff and hands over a ranked, capped list of hunches; four expensive specialists (Read, plus Grep/Glob and narrow graphify tools to close a trace on a named finding) each sweep their own labels across the whole diff independently, then settle whatever hunches landed in their slice — one spawn each, four in parallel.

### 3.1 Stage one — the scout

One spawn, `subagent_type: "pr-review-scout"`. Has Grep/Glob plus live graphify MCP tools (`get_node`, `get_neighbors`, `query_graph`, `shortest_path` — registered in `.mcp.json`, backed by `graphify.serve`, the MCP stdio server that ships inside the `graphify` pip package itself). When `GRAPH=on`, the scout calls these itself, per changed file, plus one hop deeper on up to 3 symbols each file's own lookup names as `[contains]` (file-level lookups alone are thin for code — the calls/uses/references edges live on the symbol, one hop deeper) — `build-artifacts.sh` only runs `graphify update .` beforehand to keep the index fresh (§1.5). The scout is the one that turns its own calls into `related`/`graph_coverage` per file. Verifiers never call the broad `query_graph`/`get_node` themselves; they get the scout's payoff pre-digested through `context` instead (below), and hold only `get_neighbors`/`shortest_path` under the same narrow, trace-closing license as their Grep/Glob — so the same graph exploration isn't paid for twice across five prompts. Reads the patch, manifest, brief; emits three arrays:

```json
{"graph": "off",
 "context": [
   {"file": ".claude/skills/run-mutmut/scripts/run_mutmut.py", "kind": "other",
    "related": [".claude/skills/shared-test-skills/target_discovery.py"],
    "graph_coverage": "none"}
 ],
 "hypotheses": [
   {"file": ".claude/skills/run-mutmut/scripts/run_mutmut.py", "label": "logic",
    "one_line": "sys.executable interpolated unquoted into the single --runner string mutmut word-splits",
    "related": [".claude/skills/run-coverage/scripts/run_coverage.py"], "rank": 1}
 ],
 "impacted": []}
```

**`context`** covers every changed code unit — file, `kind`, `related`, `graph_coverage`. Broadcast unchanged to all four verifiers. **`hypotheses`** may be empty, capped at **12**, ranked by suspicion — no confirmed line, no evidence, no verdict, just a guess to test first. `related` carries the paths a verifier's trace will most likely need, resolved once instead of re-discovered four times; a verifier that needs one more file `related` didn't name can now go find it itself with its own Grep/Glob, narrowly, rather than being stopped cold.

**`impacted`** may be empty and is capped at **12** — it names unchanged files that call into something this diff changed, `{file, calls, graph_coverage}`. **It is populated on both graph paths.** Two sources feed it, and neither costs an extra call:

- *The candidate list* (`impacted-candidates.txt`, built by `build-artifacts.sh` §1.9 and pasted into the scout's prompt) — unchanged files that reference a changed file's name at a word boundary, found by `git grep` at `HEAD`, capped and with the diff's own files already removed. Graph-independent, deterministic, byte-identical across two runs of the same diff. A reference is **not** a call: the scout opens each candidate and keeps only the ones that really depend on the changed unit, stamping `graph_coverage: "none"` on what it keeps from here.
- *Incoming graph edges*, when `graph: on` — the same `get_neighbors` lookup that resolves a symbol's outgoing edges into `related` also returns its incoming ones, and the scout keeps those instead of discarding them, stamped `"hit"`. Where the two sources disagree about a file, the edge wins.

This used to be graph-only, which meant `impacted` was empty on every run without a graphify index — every repo that had not installed it, i.e. every new adopter, losing the check precisely where nothing else covered it. Broadcast unchanged to all four verifiers alongside `context` — none of the diff's own lines cover an impacted file, so a verifier reads it only to check whether the change broke it, under whichever of that verifier's own labels the breakage would land under.

### 3.2 Broadcast `context`, route `hypotheses`

`context` goes whole to all four verifiers. Each `hypothesis` routes to exactly one verifier by label:

| Slice | Labels | Verifier |
|---|---|---|
| Access | `auth`, `ownership`, `security`, `data-exposure` | `pr-verify-access` |
| Data | `db`, `concurrency` | `pr-verify-data` |
| Answer | `logic`, `validation`, `control-flow`, `state`, `contract` | `pr-verify-answer` |
| Structure | `duplication`, `dead-code`, `layering`, `a11y` | `pr-verify-structure` |

A label outside this table, or one its stack can't own (`db`/`ownership` with `BE=0`, `state`/`a11y` with `FE=0`), is a scout error: drop and count it.

**Spawn all four every run, on every scope including `neither`**, in one message so they run in parallel. A slice with no hypothesis still reviews its labels on its own (job 1).

### 3.3 Stage two — the verifiers

Each verifier gets its own hypothesis list and the same `context`. `$OUT` below is this run's real directory — substitute the resolved value, never send the literal string `$OUT`:

```
Review this diff for your slice, then settle the hypotheses below.

Job 1 comes first and does not depend on the list: work the diff for your own
labels and raise anything that clears the five-field bar. Do not read the
hypotheses until job 1 is done — reading them first turns your review into a
search for more things like them.

Job 2: each hypothesis below is a guess from an agent that never opened the
file, handed to you ranked by how strongly it was suspected. Work them in
rank order and kill every one you cannot prove. If job 2 starts to crowd the
quality of what job 1 would have found, stop and report how many you left
unread — an unread hypothesis is cheaper than a thin sweep.

hypotheses:                            (may be empty — then job 1 is the whole job)
  1. <file> — <label> — <one_line>            rank 1
     related: <paths the scout resolved for this hypothesis>
  2. ...

diff:      $OUT/patch.diff
manifest:  $OUT/manifest.txt

repository root: <absolute path to the tree this patch describes>
Every path in the hypotheses and the diff is relative to that root.

<contents of $OUT/brief.txt, verbatim>

Readable without stating a reason, in addition to your standing free list:

<the wiring files list below — see "Wiring files, from the domain pack">
```

**Wiring files** — paste the domain pack's `## Wiring files` list verbatim in place of the placeholder, if the pack exists. **No domain pack** — omit the block entirely; don't invent one. **No verifier is ever told a hypothesis is real** — "settle", "kill every one you cannot prove". Rank tells a verifier what to try first, never what to trust.

**Domain pack probes are inlined too, split by slice.** `build-artifacts.sh` (§1.5) extracts the pack's `## Label probes` table once into four files — `probes-access.txt`, `-data.txt`, `-answer.txt`, `-structure.txt`, each holding only that slice's own rows — and `SKILL.md` §3's payload carries all four (`probesAccessText` etc.) into the Workflow call. Each verifier's prompt gets its own slice's text pasted in under a `domain pack` heading; empty (no pack, or a stale one) reads as "use your fallback prose," same signal as an empty `wiringFilesText`. This exists purely to avoid four independent spawns each opening and re-parsing the same ~100-line file for the ~15 lines relevant to them — same content a verifier would have read itself, delivered once instead of up to four times.

### 3.4 What the scout still decides

Every slice is reviewed by its specialist every run, no carve-out by scope. The scout still decides what gets a head start — which files a specialist opens first, which paths are pre-resolved via `related` — but that head start is no longer a hard ceiling: a specialist can grep/glob for a closing file neither the manifest nor any `related` list names. Only when that targeted search itself comes up empty does the defect get dropped, counted in `dropped_unreachable`.

### 3.5 The numbers to watch

Every verifier returns `hypotheses_received`, `hypotheses_unread`, and tags each finding `source: "hypothesis"` or `"sweep"`.

- `hypothesis` findings climbing, low kill rate → scout guessing well, widen licence/cap.
- `hypothesis` findings climbing, near-100% kill rate → scout flooding, tighten cap/prompt.
- `sweep` findings climbing → scout is missing things — an enumeration miss, measured directly.
- `hypotheses_unread` climbing → cap too generous for the model doing job 1.

A finding both stages reached stays `sweep` — the verifier found it independently.


**With §3 run as a Workflow call, §5.1–§5.3 already happened inside the script** — its return value is the parsed/deduplicated/sorted object below. Skip to §5.4 to persist and render.

### 5.1 Parse

Take the **last** fenced `json` block in each spawn's output.

```json
{"slice": ["auth","ownership","security","data-exposure"],
 "scope": "backend",
 "hypotheses_received": 3,
 "hypotheses_unread": 0,
 "findings": [{"file": "...", "line": 61, "label": "ownership", "source": "sweep",
               "failure_mode": "...", "evidence": ["...", "..."]}],
 "dropped_unreachable": 0}
```

A finding is renderable only with `file`, `line`, `label`, `failure_mode` — one missing → drop it and count the drop. `source` missing doesn't block rendering.

**There is no dismissal list.** A verifier has two outcomes per candidate: a finding that clears the five-field bar, or a silent drop. Nothing records what it considered and rejected, so a candidate the verifier believed safe leaves no trace at all — deliberately. A concrete triggering input or state plus a wrong outcome is a finding, including when nothing in the tree currently produces that state; reachability never withholds one.

`dropped_unreachable` is a per-spawn count, always present, of candidates (sweep or hypothesis) killed only because even a targeted grep/glob search could not locate the closing file — never content, never a finding in disguise. The script sums it across all four spawns into the top-level `dropped_unreachable`. Expect this number to drop sharply once verifiers have search — it now measures genuine dead ends, not the previous hard ceiling.

**`failed`, `degraded` and `clean` are slice-level verdicts.** A slice fails when its spawn returned nothing parseable. Otherwise its findings pool before dropping malformed entries; if that pool is empty, the slice is **clean**; if it's non-empty but every entry is malformed, the slice is **degraded** (`{slice, returned}` in the top-level `degraded` array); otherwise the survivors go on to dedup (§5.2) same as any other row.

The spawn's own `slice` echo is checked against the labels it was assigned (§3.2's table). A label missing from the echo lands in the top-level `slice_mismatch` array as `{slice, missing}` — treat those labels as unreviewed this run, same as a `failed` slice would be.

| Spawn returned | Means | Report as |
|---|---|---|
| `"findings": []`, or non-empty with the pool empty after malformed drop | Slice was checked, is clean | **clean** |
| Nothing parseable | Spawn crashed/timed out/drifted | **failed** — never clean |

### 5.2 Deduplicate

**Key is `file` + `line` + `label`, all three.** Same file/line, different label → both survive. Same file/line/label → keep one, its evidence entire — never splice two traces together.

### 5.3 Sort

Group by label, ordered by slice then table order within slice:

| Order | Slice | Labels, in table order |
|---|---|---|
| 1 | Access | `auth`, `ownership`, `security`, `data-exposure` |
| 2 | Data | `db`, `concurrency` |
| 3 | Answer | `logic`, `validation`, `control-flow`, `state`, `contract` |
| 4 | Structure | `layering`, `duplication`, `dead-code`, `a11y` |

Within a label: file path, then line number.

