# specialized-code-review

A branch-diff reviewer for Claude Code that reports **proven defects only**, and never edits
anything. Drop the `.claude/` directory into any git repository and you get three commands:

| Command | Does |
|---|---|
| `/pr-review [base]` | Reviews what the current branch adds against `base`. Prints a numbered index of findings — one line each. Defaults to `dev`. |
| `/explain-bug <n>` | Expands finding *n* from the last run: the full failure mode, the evidence trace with the real code at each step, and the pattern in this repo it should have followed. |
| `/generate-domain-pack` | Builds this repo's own probe corpus — cited files, lines and functions — that the reviewer compares new code against. |

## How it works, in one paragraph

A deterministic shell script builds the run's artifacts (diff at 15 lines of context, manifest,
stack scope, an orientation brief of grep-derived facts). One cheap **scout** pass maps every
changed unit and hands over a ranked, capped list of unproven hunches. Four **verifiers** then run
in parallel — Access, Data, Answer, Structure, covering fifteen closed labels between them — each
sweeping its own labels across the whole diff *first*, cold, then settling whatever hunches landed
in its slice. A hunch a verifier cannot prove dies silently; there is no "possibly", no severity
ladder and no dismissal list. Findings are merged, deduped, sorted and numbered deterministically,
then persisted so `/explain-bug` can expand any of them later.

## Requirements

**Hard — the reviewer will not run without these:**

| | Why |
|---|---|
| **A git repository** | Everything is derived from `git diff BASE...HEAD`. The script exits `2` outside a repo. |
| **A base branch that resolves** | Locally or as `origin/<base>`. The script never substitutes another base; it exits `3`. |
| **bash** | 3.2 or newer — the scripts are deliberately macOS-bash-3.2 compatible. Plus the usual `git`, `awk`, `grep`, `sed`, `find`. |
| **Claude Code** (or Cowork) with skills, subagents and the Workflow tool | The four verifiers and the scout are subagents; the fan-out is a Workflow script. |
| **`jq`** | Only for the eval tooling (`add-regression-case.sh`, `check-regression-case.sh`, `run-regression-set.sh`). The review itself does not use it. |

**Optional — recommended, not required:**

| | Why |
|---|---|
| **graphify** | A code-graph index. With it, the scout resolves callers and callees from real edges instead of grep, and stamps `graph_coverage: "hit"`. Without it, everything still runs: `related` falls back to Grep/Glob and `impacted` falls back to the script's own deterministic candidate list. `GRAPH=off` is a supported path, not a degraded one. |

## Install

### 1. Copy `.claude/` into the target repo

```bash
cp -R /path/to/specialized-code-review/.claude /path/to/your-repo/
```

If the target repo already has a `.claude/`, merge instead of overwriting — the pieces are
`agents/pr-*`, `skills/{pr-review,explain-bug,generate-domain-pack}`, `workflows/pr-review-verify.js`
and `references/{pr-review-domain.md,eval/}`. Nothing else in `.claude/` is touched.

### 2. Check your base branch

`/pr-review` defaults to **`dev`**. If your integration branch is `main`, either pass it every time
(`/pr-review main`) or change the default in
`.claude/skills/pr-review/scripts/build-artifacts.sh` (`BASE_ARG="${1:-dev}"`).

### 3. Generate the domain pack

**This is the step that makes the reviewer good, and it is not optional in practice.**

```
/generate-domain-pack
```

`.claude/references/pr-review-domain.md` ships **empty on purpose** — every citation in it is
repo-specific and none of it transfers between repos. With an empty pack the reviewer still runs,
but every label falls back to generic, uncited probes: it knows what an ownership bug looks like in
general, and nothing about how *your* repository does ownership correctly. The pack is what lets a
verifier close an evidence trace against a real line in your code.

The skill generates from a worktree scoped to your base branch, so it can never cite code that the
branch under review introduced. It removes that worktree as a verified final step.

### 4. Run it

```
/pr-review              # against dev
/pr-review main         # against another base
```

### 5. (Optional) Wire up graphify

Install graphify — the agent definitions assume the pip package that ships both the `graphify` CLI
and the `graphify.serve` MCP stdio server — then create an index and register the server in
`.mcp.json` at your repo root:

```jsonc
{
  "mcpServers": {
    "graphify": {
      "command": "python3",
      "args": ["-m", "graphify.serve"]
      // check graphify's own docs for the exact command and args
    }
  }
}
```

```bash
graphify update .        # creates graphify-out/graph.json
```

The agents call four tools by exact name: `get_node`, `get_neighbors`, `query_graph`,
`shortest_path`. If `graphify-out/graph.json` is absent, `graphify` is not on `PATH`, or
`graphify update` fails, the run silently sets `GRAPH=off` and proceeds. Set
`PR_REVIEW_NO_GRAPH=1` to force that path.

## What ships empty, and fills up as you use it

| File | Fills with | How |
|---|---|---|
| `references/pr-review-domain.md` | This repo's cited probes, wiring files, stack prefixes, brief regexes, dependency shortlist | `/generate-domain-pack` |
| `references/eval/review-corrections.md` | Every finding a human dismissed, written as a rule with the guard that makes the pattern safe **and** the condition that would make it unsafe — plus the per-label acceptance tally | By hand, after each run's verdicts |
| `references/eval/regression-set/cases/` | Every finding a human accepted, as ground truth a later change to the reviewer must not lose | `scripts/add-regression-case.sh <label> <file> <line>` |

An entry seen **twice** in the corrections ledger gets promoted into the scout's own
*Known non-defects* section; label corrections promote on first sighting. That promotion is the
reviewer's only learning mechanism — it does not learn from your past fix commits, and
`review-corrections.md` explains at length why that was rejected as a design.

## Environment variables

All read by `build-artifacts.sh`.

| Variable | Default | Does |
|---|---|---|
| `PR_REVIEW_NO_GRAPH` | unset | `1` skips the graphify refresh entirely (`GRAPH=off`). |
| `PR_REVIEW_PACK` | `.claude/references/pr-review-domain.md` | Use a different domain pack — for testing, or running a foreign repo's pack. |
| `PR_REVIEW_HEAD` | `HEAD` | Diff `BASE...<sha>` instead of the current HEAD, without checking anything out. Used to replay a historical diff for the regression set. |
| `PR_REVIEW_LARGE_DIFF` | `2500` | Changed-line threshold for the large-diff warning. A warning only — nothing is ever trimmed. |
| `PR_REVIEW_KEEP_DAYS` | `7` | Age before a stale `.git/pr-review.*` run directory is pruned. |
| `PR_REVIEW_IMPACTED_CAP` | `24` | Max impacted-caller candidates the script emits. |

## Where things are written

| Path | What |
|---|---|
| `.git/pr-review.XXXXXX/` | One directory per run, holding that run's artifacts. Pruned after `PR_REVIEW_KEEP_DAYS`. |
| `.git/pr-review/findings.json` | The last run's merged findings — the one fixed path `/explain-bug` reads. |

Both live under `.git/`, so nothing the reviewer produces can ever be committed by accident.

## Troubleshooting

| Symptom | Meaning | Fix |
|---|---|---|
| `error: not inside a git repository` (exit 2) | — | Run from inside the repo. |
| `error: base 'dev' resolves neither locally nor as origin/dev` (exit 3) | Your integration branch isn't `dev` | Pass it: `/pr-review main`. See step 2. |
| `error: no merge base` (exit 4) | Unrelated histories | Check you passed the right base. |
| `Nothing to review` with files changed | Every changed file was excluded (lockfiles, build output, binaries, images) | Expected. The exclusion list is §1.4 of the script. |
| `PACK_PRESENT=0` | No domain pack | Run `/generate-domain-pack`. The review still works, generically. |
| `PACK_STALE=1` | A citation in the pack no longer resolves — the file moved, or its line number is now past EOF | Regenerate the pack. Until then every verifier falls back to generic probes. |
| `PACK_INVALID=1` | The pack fails `validate-pack.sh`'s format contract (see `model/FORMAT.md`) — an unfenced wiring block, a malformed label row, a non-closed-list label, invalid brief-probes bash, or an unwrapped citation | Fix what the warning names, or regenerate the pack. Sets `PACK_STALE=1` too — same fallback: generic probes until fixed. |
| `warning: domain pack is missing (or has renamed) these section headings` | A `## Heading` was retyped | Fix the heading exactly. That section is silently empty until you do — this warning is the only signal. |
| `BRIEF_DEGRADED=1` | The pack's `## Brief probes` block raised an error at run time (bash -n can't catch everything — a runtime "command not found" still slips through) | `brief.txt` may be missing a field. See the stderr note for the actual error; fix the probes block. |
| `LEDGER_STALE=1` | A citation in the corrections ledger has drifted | Fix the citation. Warning only: the ledger is still passed through, because dropping every rule over one bad line number would un-suppress every other rule's false positive. |
| `DIRTY=1` in the report | You have uncommitted changes | They are **not** in the diff. Commit them if you want them reviewed. |
| Report names a slice as `Failed` or `Degraded` | That verifier returned nothing parseable, or nothing renderable | Those labels were **not reviewed** on this branch. Never read the silence as clean — re-run. |
| A finding's line number is wrong | The findings were recorded against an older HEAD | `/explain-bug` warns when HEAD has moved. Re-run `/pr-review` to renumber. |

## Design notes worth knowing before you change anything

- **Step numbers are stable.** `SKILL.md`, the agent definitions and the workflow script all cite
  each other as `§1.5`, `§3.2`, `§5.4`. Renumbering breaks cross-references in five files.
- **Everything deterministic lives in the shell script**, so two runs against the same diff produce
  a byte-identical brief and the same finding numbers. If you find yourself asking a model to
  compute something reproducible, it belongs in `build-artifacts.sh`.
- **The brief carries facts, never suspicions.** `money/amount lines: 10` ships; "watch the
  rounding" does not — a spawn told what to suspect confirms the suspicion instead of reading the
  code.
- **Verifiers do their own sweep before they read the scout's hunches**, and that order is load
  bearing. A verifier that reads the guesses first becomes an extension of the agent it exists to
  correct.
- **Reachability never decides whether a defect is real.** "Nothing calls this yet" is a reason a
  bug has not been *hit*, never a reason it is not *there*.
- **Re-run the whole regression set after any change to the reviewer** — a change that recovers one
  finding while losing another is not progress, and only a full re-run shows it.
