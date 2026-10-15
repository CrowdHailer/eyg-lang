# Slack channel authorization with Gleam and EYG

A runnable prototype for signing in with Slack, authorizing application pages,
and checking GitHub PR submitters and reviewers against Slack channel membership.
Built from `bot/datalog`; policy evaluation uses that branch's EYG interpreter
and the existing [`authorization/rbac.eyg`](../../eyg_packages/authorization/rbac.eyg).

## Run it

Requires Gleam and Bun. From the repository root:

```sh
cd packages/channel_policy
gleam run --runtime bun
gleam test --runtime bun
gleam format --check src test
gleam build --warnings-as-errors
```

Run these commands from this package directory: the example loads the existing
EYG policy using `../../eyg_packages/authorization/rbac.eyg`. The interpreter and
parser are local Gleam dependencies, so the demo does not depend on an installed
`eyg` executable. This package targets JavaScript, matching the EYG interpreter.

### What is implemented

| Component | Implementation |
| --- | --- |
| Login | Single-use state, browser binding, nonce/workspace checks, claim and session expiry |
| Account linking | Verified-provider boundary, stable GitHub IDs, conflict detection |
| Slack membership | Cursor pagination, deduplication, atomic snapshots, freshness and coverage checks |
| Authorization | Real EYG Datalog evaluation, bounded execution, native proof trees with matched facts and successful predicates |
| Page/API gate | 401/403/200 results; protected loader runs only after permission is established |
| PR rules | Submitter, reviewer, or both; all paths, additions, deletions and both sides of renames |
| Reviews | Latest decisive review, current-head approval, no self-approval, conservative timestamp ties |
| Check orchestration | Fetch PR, publish pending, refresh membership, evaluate, publish success/failure |
| External services | Explicit mock adapters for OIDC exchange, GitHub identity, Slack membership, PR fetch and check publishing |

This is an executable library/demo, with in-memory state and no HTTP listener.
OAuth/JWT cryptography, cookies, persistence, webhooks, scheduling and real API
transport are host integration work. The mock OIDC adapter does **not** validate
real tokens; its fixed codes are demonstration fixtures.

## Walkthrough

For the narrated video, open [`video/output/watch.html`](video/output/watch.html)
or [`video/output/walkthrough.mp4`](video/output/walkthrough.mp4). The video includes
policy editing, login, real isolated Git commits, mocked PR approval and the LLM
quota example. See [video generation instructions](video/README.md) to reproduce it.

### 1. Set up the people and permissions

The fixture in [`mock.gleam`](src/channel_policy/mock.gleam) defines:

| Person | Slack account | GitHub ID | Channel |
| --- | --- | --- | --- |
| Ada | `T_ACME/U_ADA` | `101` | `C_PLATFORM` |
| Bea | `T_ACME/U_BEA` | `102` | `C_PLATFORM` |
| Cal | `T_ACME/U_CAL` | `103` | `C_FINANCE` |

The application is `console`; the repository is `acme/app`.

- Platform members can view `/deployments`, submit changes under `infra/`, and
  approve changes under `infra/`.
- Finance members have the equivalent rights to `/finance` and `finance/`.
- Everything else defaults to denial.

IDs, not display names or channel names, participate in the policy. The
workspace is part of every membership join. A resource also includes its
application/repository, so equal paths in different applications do not collide.

### 2. Sign in with Slack

`identity.begin` stores a pending attempt containing state, browser binding,
nonce, expected workspace and expiry. The host redirects to Slack OIDC.

The callback calls `identity.finish`, which consumes the attempt, checks the
browser binding, and calls `Oidc.exchange`. That adapter returns verified claims.
The host obtains an opaque session with an expiry no later than the claims.
Always persist the returned login state, including after a failed exchange.

In the demo, `mock.login("ada-code")` runs this process at a fixed clock time.
The static strings stand in for random state/nonce values and a real code.

### 3. Link GitHub to the authenticated Slack account

After GitHub OAuth, `identity.link_github` uses the adapter's authenticated-user
lookup to associate the stable GitHub ID with the current Slack account. The
caller cannot supply the Slack identity independently of the session.

Repeated linking is idempotent. Reassigning an existing link within a workspace
is rejected. The same GitHub identity may link accounts in different workspaces.
The demo links all three fixture users this way.

### 4. Refresh channel membership

`slack.refresh` requests every page of every configured channel. The mock returns
Bea on **page two**, exercising the real pagination loop. An empty page with a
next cursor is not treated as the end. Any failed page rejects the whole refresh.

A snapshot records the channels actually fetched, their memberships and its
observation time. Evaluation checks that the relevant channels were fetched and
that the snapshot is younger than the configured age (60 seconds in the demo).
Refreshing replaces memberships, so departed members are removed.

### 5. Evaluate the page permission using EYG

`policy.page` checks the session and then passes typed host data to
`engine.authorize`. Conceptually it supplies:

```text
Member({tenant: "T_ACME", actor: "U_ADA", role: "C_PLATFORM"})
RolePermission({
  tenant: "T_ACME", role: "C_PLATFORM", action: "view",
  resource: {kind: "page", scope: "console", path: "/deployments"},
  policy: "deployment-page"
})
```

The existing EYG module contains the actual rule:

```eyg
let authorize = (db, request) -> {
  let {tenant, actor, action, resource} = request
  resolve Permit @{
    db,
    rule Permit({tenant, actor, action, resource, role, policy}) {
      var role
      var policy
      Member({tenant, actor, role}),
      RolePermission({tenant, role, action, resource, policy})
    }
  }
}
{authorize}
```

Gleam parses the trusted module once, supplies `db` and `request` as interpreter
values, and executes with an interpreter-transition budget. User data is never
interpolated into source. There is no separate Datalog evaluator in this package.
An exhausted budget, unexpected effect, malformed result or empty permit list
denies access. Every returned permission now carries the engine-generated proof
tree, including the matched facts and any successful guards. A nonempty permit
list without a corresponding engine derivation is rejected by the host.

The demo prints:

```text
ALLOW /deployments
  deployment-page via T_ACME/C_PLATFORM
DENY /finance: No channel membership grants this action
```

For actual page or API handlers, use `application.handle`. Pass a trusted
session looked up by the server and an application-selected permission route.
For example, `/api/deployments` can use the same `/deployments` permission as its
HTML page. Put the protected data load in the callback; it is never called on
401 or 403. Map the returned response into your web framework's response type.

### 6. Check a PR

The fixture PR #42 changes `infra/main.tf`. Ada is its submitter; Bea has approved
`head-v1`. `github.run` refreshes membership and calls `github.evaluate` with
`SubmitterAndReviewer`. The same EYG rule is queried with `change` for Ada and
`approve` for Bea.

The mock publisher prints `PENDING`, then `SUCCESS`. The report contains two
proofs: `infra-submitter` for Ada and `infra-reviewer` for Bea.

Every path must satisfy the configured mode. Multiple paths may have different
reviewers. For renames, both old and new paths must pass. A rename from
`finance/report.csv` to `infra/report.csv` therefore cannot evade finance rules.
Incomplete file lists are rejected by comparing against `changed_file_count`.

`Submitter` checks the PR creator's permission to submit those changes for merge.
It does not attest to the original author of every line or every commit, nor
prevent local edits or creating a branch. `Reviewer` allows other people to
submit changes provided an eligible channel member approves them.

### 7. Revoke and reevaluate

The next demo step removes Bea from the Slack fixture and reruns PR #42. The
same head now produces `PENDING`, then `FAILURE`, because her approval no longer
has channel membership behind it.

The following step restores membership but changes the head to `head-v2`.
Bea's old approval still does not qualify. The final page request uses an expired
membership snapshot and is denied even though Ada's session is still valid.

### 8. Limit access to an LLM inference endpoint

The additional policy in [`policies/llm_quota.eyg`](policies/llm_quota.eyg) joins
trusted `Usage` and `Quota` facts for the same workspace, authenticated user,
endpoint and billing window. It permits the `infer` action only when
`0 <= used < limit`. A quota fact is the grant of inference access for that scope;
this example does not additionally require Slack channel membership.

Run the example from this package directory:

```sh
gleam run --runtime bun -m channel_policy/quota_example
```

Expected decisions:

```text
49/50 requests: ALLOW: reserve one request, then forward to the model
50/50 requests: DENY: Inference denied: usage limit reached or quota does not match
```

Here usage is **admitted inference requests**, not tokens. The EYG rule uses
`!equal(!int_compare(used, limit), Lt({}))` for strict comparison. The Gleam
[`quota.authorize`](src/channel_policy/quota.gleam) host checks session validity
and usage-snapshot freshness before invoking that rule. Missing matches,
negative usage, a zero limit, expired sessions and stale usage deny access.

The example evaluates a trusted meter at 49 and then at 50; it does not send an
HTTP inference request or implement a billing database. A real gateway must
check and reserve the next request **atomically in trusted storage** before
forwarding to the model, so concurrent callers cannot both spend the last slot.
The host selects the current billing window and endpoint. Never accept usage,
limits, account identity or the billing window from untrusted request data.

## Changing the rules

### Inspecting the allowed reason

`policy.Allowed` contains `Proof` records with a `tree` field. PR
`Report.evidence` retains those trees for every permitted path and actor. The
demo prints them, and the GitHub check summary includes them on success.
`quota.authorize_with_proofs` exposes the inference proof; the existing
`quota.authorize` convenience function returns only allow/deny.

```text
Permit(U_ADA, view, /deployments) [rule 0]
  Member(T_ACME, U_ADA, C_PLATFORM)
  RolePermission(T_ACME, C_PLATFORM, view, /deployments)
```

The quota tree adds the matched `Quota` and `Usage` facts plus the successful
action, nonnegative-usage and strict-less-than guards. The video shows each
passing policy example's actual captured tree. Its
[`proofs.json`](video/output/proofs.json) contains full fact fields, predicate
source, bindings and child nodes.

The core API is [`eyg/interpreter/explain`](../gleam_interpreter/src/eyg/interpreter/explain.gleam).
It records one finite first-discovered witness per answer, including recursive
derivations. Read [Datalog proof trees](../../guides/query_proofs.md) for API and
semantics. Login, freshness and commit-specific review checks are host checks;
they are identified separately in the video.

### Configuring grants

Edit `mock.rules()` or supply a `policy.Policy` from your trusted configuration:

```gleam
policy.Grant(
  "payments-reviewers",
  policy.Approve,
  policy.Directory("acme/app", "src/payments"),
  slack.Channel("T_ACME", "C_PAYMENTS"),
)
```

`Directory` matches descendants on a path-component boundary, not arbitrary
globs: `infra/` does not include `infra-other/`. Supply the directory without a
trailing slash. Use `Exact(File(...))` for a single file and `Exact(Page(...))`
for a page. File paths are repository-relative POSIX paths; dot segments, empty
segments, backslashes and NUL are rejected rather than normalized. Hosts supply
canonical page permission routes after URL decoding/routing.

Matching grants are alternatives (OR). All changed paths and both enabled PR
requirements must pass (AND). A rule requiring *two* different teams to approve
the same file would need an additional requirement group, not two OR grants.

## Connecting real services

The adapters are function fields in Gleam records. Replace `mock.gleam` at the
composition root; policy code uses the same interface.

| Boundary | Real implementation |
| --- | --- |
| `identity.Oidc.exchange` | Slack OIDC code exchange using a maintained OIDC library; validate JWT signature/JWKS, issuer, audience, nonce and expiry before returning `Claims` |
| `identity.link_github` callback | Resolve a GitHub OAuth access token through `GET /user`, returning its stable numeric ID as a string |
| `slack.Client.members` | Call `conversations.members` using the installation token for `Channel.workspace`; map `response_metadata.next_cursor` to `MemberPage.next` |
| `github.Client.fetch` | Fetch PR metadata, all changed-file pages and all review pages, returning errors for incomplete results; ensure the head is stable during collection |
| `github.Client.publish` | Create/update the GitHub App's check on `Check.head`; map pending to in-progress, success/failure to completed conclusions |

Slack login uses `openid` (and optional `profile`/`email`). Request API scopes in
a separate app-installation flow: `channels:read` for public membership and
`groups:read` for private membership. Invite the bot to private policy channels.
Channel invite/join controls become controls over the corresponding permissions.

For the GitHub App, read pull requests and write checks. Fetch by the base
repository identity, collect reviews' current states (including dismissals),
and use the actual head SHA. The demo rejects ambiguous conflicting reviews at
the same timestamp. Observe API pagination/result limits rather than treating
a truncated response as a complete PR.

To enforce the outcome, require PRs and the `channel-policy` check in the target
branch's ruleset, select your GitHub App as its source and configure bypass
permissions deliberately. Load rules from deployed configuration or the trusted
base branch. Running code or policy from the PR under review would let the
submitter change their own authorization check.

### Host state and event processing

- Persist login attempts with atomic single-use consumption, sessions and account
  links; the demo's immutable in-memory values are not a multi-worker session store.
  Bind both OAuth callbacks to the browser, use secure session cookies, and check
  account deactivation when refreshing identity/membership information.
- Verify incoming Slack/GitHub webhook signatures before dispatch. Refresh after
  membership changes and periodically reconcile; rerun affected open PRs on
  membership changes, review changes, new commits and trusted policy changes.
- Serialize evaluations per PR and discard superseded jobs so a delayed older
  job cannot overwrite a newer denial. Use the latest coherent PR/head snapshot.
- Schedule reevaluation before membership freshness expires. GitHub does not
  automatically expire a successful check when a person leaves a Slack channel.
  A fetch/publish outage cannot itself invalidate an already-green remote check.
  If membership must hold at the actual instant of merging, use a controlled
  merge service that reevaluates immediately before merging the expected head,
  with direct merge bypasses disabled. Webhook/check-based enforcement has a
  revocation delay; the demo's manual rerun makes that boundary explicit.

## Code map

| File | Responsibility |
| --- | --- |
| [`identity.gleam`](src/channel_policy/identity.gleam) | Login lifecycle, sessions and linked identities |
| [`slack.gleam`](src/channel_policy/slack.gleam) | Membership collection and snapshot validity |
| [`engine.gleam`](src/channel_policy/engine.gleam) | Host-value bridge to the existing EYG evaluator |
| [`policy.gleam`](src/channel_policy/policy.gleam) | Resource selectors, trusted facts and permission decisions |
| [`application.gleam`](src/channel_policy/application.gleam) | Server-side page/API enforcement |
| [`github.gleam`](src/channel_policy/github.gleam) | PR-wide policy and check orchestration |
| [`mock.gleam`](src/channel_policy/mock.gleam) | Replaceable service adapters and fixture configuration |
| [`channel_policy.gleam`](src/channel_policy.gleam) | Six-step executable walkthrough |
| [`test/`](test/) | End-to-end allow/deny and failure-path tests |

Further background: [EYG authorization tutorial](../../guides/authorization.md),
[Slack OIDC](https://docs.slack.dev/authentication/sign-in-with-slack/),
[Slack membership API](https://docs.slack.dev/reference/methods/conversations.members/),
[GitHub rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets).
