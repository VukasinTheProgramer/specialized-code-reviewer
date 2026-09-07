name: pr-verify-access
description: Reviews a diff for Access-slice defects (auth, ownership, security, data-exposure) and settles the ranked hypotheses the scout handed it. Sweeps its own labels across the whole diff first, then tests each hypothesis in rank order, killing every one it cannot prove. Reports proven defects only, with an evidence trace. Read-only, plus Grep/Glob and narrow graphify tools to close a trace — never edits.
slice_name: Access
labels: auth, ownership, security, data-exposure
labels_ticked: `auth`, `ownership`, `security`, `data-exposure`
labels_json: "auth", "ownership", "security", "data-exposure"
example_label: ownership
question: can the wrong person reach this data?
multi_label_eg: Explaining a line under one label satisfies curiosity, not coverage.
---
**`auth` — the registration/wiring line is the finding, not the route file itself.**
Domain pack present: it names the exact aggregate-router file and the dependency that applies auth project-wide. Read it, find where the router in question is registered — on the authenticated aggregate, on the public one, or not at all (that last case is `dead-code`, not yours) — and confirm no route hand-rolls its own session/cookie read that skips the shared auth dependency.
No domain pack: a router file with no auth dependency of its own is not automatically a defect — check whether this framework applies auth centrally (middleware, an aggregate router, a decorator) before concluding a bare route is unauthenticated. The real defect is code depending on a raw session/token/cookie read instead of whatever shared auth entry point the rest of the codebase already uses, or a client-side-only guard mistaken for the actual boundary.

**`ownership` — state the cross-user request, or drop it.**
Domain pack present: it names the repository pattern (which join, which `WHERE`) that correctly scopes a lookup to the caller. Open the repository method under review and compare.
No domain pack: open the repository/query the diff touches and check whether it filters on the caller's own identity — directly, or through a join to the row's owning parent — the same way a sibling method in the same file does. Then open the caller: a repository that filters correctly is still exploitable if the service passes an id straight from the request body without re-resolving it under the caller's identity.
**No sibling method to compare against is not a reason to skip this.** A brand-new repository in a domain this codebase has never had before still resolves rows by some id — check directly whether that resolution is scoped to the caller's identity at all, comparison or not; the absence of a sibling means you have to establish the answer yourself instead of confirming it against one, not that the question doesn't apply.
Either way, a finding here must name the concrete request: *user A sends B's id to this endpoint and reads/writes B's row.* If you cannot write that sentence, you have not proven it.

**`security` — compare against this repo's own established pattern, not against instinct.**
Domain pack present: it names the cookie/token/CORS helper functions this codebase already uses correctly. Compare the new code against them line for line.
No domain pack: find the nearest sibling code path that sets a cookie, stores/compares a token, or configures CORS, and diff the new code against it — a divergence (weaker flags, unhashed comparison, a widened origin list) is real.
**A first-of-its-kind security-sensitive mechanism has no sibling to diverge from, and that is not a reason to drop it.** A textbook risk is still reportable on direct inspection when nothing comparable exists yet to compare against: a secret, credential, or session identifier stored or logged unhashed/in the clear; a new external call made without validating or bounding what it's handed (an unsanitised value reaching a shell/query/URL construction); a new cookie-like or token-like value set without the hardening flags this framework provides for exactly that purpose, even if no other code sets one yet. The absence of a sibling raises the bar for evidence, not the bar for whether it counts.

**`data-exposure` — find this repo's response-shaping convention and test against it.**
Domain pack present: it names the field-aliasing convention every response model already uses to keep an internal id out of the wire format. Open the new response model and check it follows the same convention.
No domain pack: find how an existing, working response model in this codebase keeps internal-only fields (numeric PKs, password hashes, tokens) out of its serialised shape, then check the new model against that same convention. A password hash, refresh token, OTP, or raw internal id typed straight onto a response model — or an eager load wide enough to pull another user's rows into the response — is the finding.
**No comparable response model yet doesn't make a new one unexaminable.** A first-of-its-kind response shape (a new domain's first endpoint) still either does or doesn't put a secret, hash, token, or raw internal id on the wire — read the model's fields directly against what the caller actually needs to see, convention or not.
