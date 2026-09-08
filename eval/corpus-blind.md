# Blind corpus — gate 1 BETWEEN extension

Not this project's own history. Chosen per `eval/gate-1.md`'s decision to
use a genuinely blind, non-self-referential repo for the BETWEEN
extension, fixing the exact weakness `eval/corpus.md` flagged from day
one and the deviation-overlap N/A in `eval/week-5-report.md` traced back
to.

**Repo:** `Boskov sajt` (local path:
`/Users/vukasinsavkovic/Documents/Boskov sajt`, remote
`github.com/VukasinTheProgramer/boskov-sajt`) — an Astro + Tailwind +
TypeScript static site for a water-dispenser business. Small (4 commits
total, this repo's entire history), genuinely unrelated code and domain
to this project. Never reviewed by me before this run.

Domain pack generated fresh for this repo specifically (its own real
conventions, not a copy of this project's pack — see the generation
agent's report, folded into this file once it lands), from a worktree
frozen at `ec8bc52` (current HEAD at generation time) so no record cites
code introduced by any of the 3 diffs below.

| id | base | head | what it does |
|---|---|---|---|
| b01 | `3c9d966` | `c15064a` | Initial Astro site build — components, layouts, pages, data files, all created in one commit. |
| b02 | `c15064a` | `02d85b2` | Refactor: centralize site contact info into `src/data/site.ts`. |
| b03 | `02d85b2` | `ec8bc52` | Docs only: add `TODO.md` tracking remaining launch work. |

Reviewed via the same pipeline scripts (`build-artifacts.sh`,
`validate-pack.sh`, `model/pack-heading-check.sh`, `parse_conventions.py`)
copied untracked into Boskov sajt's own tree at the same relative paths
this project uses — same portability model `tests/run-integration.sh`
already exercises against a throwaway repo, just against a real one here.
Agent definitions (`pr-review-scout`, `pr-verify-*`) are resolved from
this session/project as usual — stack-agnostic by `core/`'s own doctrine,
nothing repo-specific needed on Boskov sajt's side for those.
