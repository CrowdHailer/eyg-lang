---
name: Authorization with query literals
description: Build and test role, relationship, delegation, and agent policies with typed EYG queries.
slug: authorization
---

# Authorization with query literals

An authorization policy turns trusted facts and a request into a decision.
EYG query literals let us express the relationships that justify that decision,
while effects give the host a place to enforce it. This tutorial builds from
roles to agents carrying out long-running tasks for different companies.

Every EYG block below is an independent, executable example. Each returns
`True({})`; the CLI integration suite executes the blocks directly from this
document. Imports are relative to this file. The implementations and additional
allow/deny tests live in [the authorization package](../eyg_packages/authorization/).
From the repository root, run all its examples and adversarial cases with:

```sh
eyg script eyg_packages/authorization/entry.eyg
```

Use a CLI built from this branch: released CLIs predating query literals cannot
parse these programs. See [installation from source](./install_from_source.md).

## The trust boundary

The examples accept a database snapshot, authenticated identity, and time from
the host. A request supplies the operation and resource; it cannot choose its
own identity or facts. Empty results mean denial. Rules are pure, and effect
handlers perform an operation only after a decision permits it.

| Input | Trusted producer |
| --- | --- |
| Tenant and actor | Authentication/session layer |
| Membership, ownership, team policy | Organization administrators |
| Approval, agent and task state | Their respective control services |
| Delegation | The admission service after checking the issuer's authority |
| Current time and snapshot revision | Host handling this request |

Tables are composable values, **not authenticated containers**. The `db`
argument in this tutorial is a trusted, finite collection of base facts. Do not
let callers submit arbitrary tables, rules, or derived facts such as `Permit`,
`Can`, `Proof`, or `Grant` where the enterprise policy generates them. Such an
input could assert its own authorization. Types check schemas; they do not
establish who is entitled to assert a fact.

## 1. Role based access control

Join a user's membership to a role's permission. Reusing the lexical values
`tenant`, `actor`, `action`, and `resource` constrains both relations to this
request. Only names declared with `var` are logic variables. Including `tenant`
in every join keeps identically named roles in different companies separate.

```eyg
let tenant = "acme"
let actor = "alice"
let action = "read"
let resource = "/docs/report"
let permits = resolve Permit @{
  fact Member({tenant: "acme", actor: "alice", role: "reader"}),
  fact RolePermission({tenant: "acme", role: "reader", action: "read", resource: "/docs/report"}),
  fact RolePermission({tenant: "beta", role: "reader", action: "write", resource: "/docs/report"}),
  rule Permit({actor, resource, role}) {
    var role
    Member({tenant, actor, role}),
    RolePermission({tenant, role, action, resource})
  }
}
!equal(permits, [{actor: "alice", resource: "/docs/report", role: "reader"}])
```

The reusable `rbac.authorize(db, request)` also returns the permission's
`policy` identifier. Changing `action` to `write` gives no permission: the
matching permission belongs to another tenant. The package tests cover this,
missing membership, and an empty database.

## 2. Relationship based access control

Resources often form a hierarchy: an organization contains a team, which owns
a document. `relationships.view` derives `Can` from `Grant`, then propagates it
along `Child({tenant, parent, child})`. Resolving a query repeats those rules
until no new facts appear. The direction of `Child` matters: access flows from
parent to child, never in reverse.

```eyg
let {relationships} = import "../eyg_packages/authorization/index.eyg"
let db = @{
  fact Grant({tenant: "acme", actor: "alice", action: "read", resource: "engineering"}),
  fact Child({tenant: "acme", parent: "engineering", child: "atlas"}),
  fact Child({tenant: "acme", parent: "atlas", child: "report"})
}
let request = {tenant: "acme", actor: "alice", action: "read", resource: "report"}
let allowed = relationships.authorize(db, request)
let denied = relationships.authorize(db, {action: "write", ..request})
!equal({allowed, denied}, {
  allowed: [{tenant: "acme", actor: "alice", action: "read", resource: "report"}],
  denied: []
})
```

These rules only rearrange existing values. Duplicate elimination makes even
a cyclic `Child` graph finite. Adding arithmetic or growing lists to recursive
heads changes that argument: not every EYG query has a finite fixed point.

## 3. Delegation

A `Delegate` relationship allows its owner to pass every held right to another
principal. A second recursive join makes delegation transitive: Alice can pass
a right to a bot, which can pass it to a worker. This chapter deliberately has
no narrowing or expiry; it makes the risks of unrestricted delegation visible.

```eyg
let {delegation} = import "../eyg_packages/authorization/index.eyg"
let db = @{
  fact Grant({tenant: "acme", actor: "alice", action: "read", resource: "report"}),
  fact Delegate({tenant: "acme", owner: "alice", recipient: "bot"}),
  fact Delegate({tenant: "acme", owner: "bot", recipient: "worker"})
}
let request = {tenant: "acme", actor: "worker", action: "read", resource: "report"}
!equal(delegation.authorize(db, request), [request])
```

Delegation cannot invent a new action or resource. A cycle alone grants
nothing; it needs a root `Grant`. The next chapter replaces this broad
relationship with explicit, limited capabilities.

## 4. Attenuated delegation

Attenuation means each delegation can only reduce authority. A `Delegation`
names one action, a resource subtree, and an expiry. It must keep the same
tenant and action, stay within the owner's scope, and expire no later than the
owner's capability. Time is passed in, so the rule remains pure and repeatable.
Expiry is exclusive: a capability with `expires: 150` is invalid at time 150.

```eyg
let {attenuation} = import "../eyg_packages/authorization/index.eyg"
let db = @{
  fact Grant({tenant: "acme", actor: "alice", action: "read", scope: "/docs", expires: 200}),
  fact Delegation({tenant: "acme", owner: "alice", recipient: "bot", action: "read", scope: "/docs/reports", expires: 150})
}
let request = {tenant: "acme", actor: "bot", action: "read", resource: "/docs/reports/october"}
let expired = attenuation.authorize(db, request, 150)
let outside = attenuation.authorize(db, {resource: "/docs/private", ..request}, 100)
let present = attenuation.authorize(db, request, 100)
!equal({expired, outside, present}, {
  expired: [], outside: [],
  present: [{tenant: "acme", actor: "bot", action: "read", resource: "/docs/reports/october", scope: "/docs/reports", expires: 150}]
})
```

Scopes use normalized absolute POSIX resource paths. `/docs-other` is not a
child of `/docs`; dot segments are normalized and above-root paths, NUL, and
backslash are rejected. This is a resource naming convention. Filesystem
symlinks require separate host enforcement, as discussed in chapter 7.

## 5. Provenance: explain the permission

Attach a stable, host-assigned `id` to every root grant and delegation.
`provenance.authorize` returns the original issuer and the ordered grant chain
supporting the request. The order is newest delegation first, root grant last.
Distinct valid chains remain distinct explanations.

```eyg
let {provenance} = import "../eyg_packages/authorization/index.eyg"
let db = @{
  fact Grant({tenant: "acme", actor: "alice", action: "read", scope: "/docs", expires: 200, id: "root-7"}),
  fact Delegation({tenant: "acme", owner: "alice", recipient: "bot", action: "read", scope: "/docs/reports", expires: 150, id: "delegation-9"})
}
let request = {tenant: "acme", actor: "bot", action: "read", resource: "/docs/reports/october"}
!equal(provenance.authorize(db, request, 100), [{
  tenant: "acme", actor: "bot", issuer: "alice", action: "read",
  resource: "/docs/reports/october", scope: "/docs/reports", expires: 150,
  grants: ["delegation-9", "root-7"]
}])
```

A naive rule appending IDs on every cycle would generate infinitely many
proofs. This implementation carries a `seen` list and excludes repeated
principals within one chain. Every edge narrows scope and expiry, so removing
a cycle cannot remove authority needed for a subsequent edge. Simple paths
therefore suffice for this policy. Their number can still grow exponentially;
bound trusted input sizes and execution resources in the host.

These explanations are not cryptographic attestations or a complete execution
trace. Audit the authenticated request, time, snapshot revision, selected
proofs, policy version, and eventual effect outcome together. The snapshot
retains the membership, approval, and lifecycle facts behind a decision.

## 6. A rule about creating rules

An administrator may permit only read/write delegations, even when a user has
additional rights. `admission.admit(db, identity, proposal, now)` applies this
meta-policy using `AllowedAction` facts and the same attenuation checks.
It returns `Ok(Table)` containing one admitted `Delegation`, or `Error(reason)`.
The service stores the admitted fact with the issuer and snapshot revision.

```eyg
let {admission, attenuation} = import "../eyg_packages/authorization/index.eyg"
let db = fact Grant({tenant: "acme", actor: "alice", action: "read", scope: "/docs", expires: 200})
let identity = {tenant: "acme", actor: "alice"}
let proposal = {recipient: "bot", action: "read", scope: "/docs/reports", expires: 150, id: "new-1"}
match admission.admit(db, identity, proposal, 100) {
  Error(_) -> { False({}) }
  Ok(permission) -> {
    let request = {tenant: "acme", actor: "bot", action: "read", resource: "/docs/reports/october"}
    !equal(attenuation.authorize(@{db, permission}, request, 100), [{
      tenant: "acme", actor: "bot", action: "read", resource: "/docs/reports/october",
      scope: "/docs/reports", expires: 150
    }])
  }
}
```

Here, “creating a rule” means instantiating this trusted delegation template.
It does not mean accepting arbitrary EYG source or a table from the requester.
The service sets the identity and ID, validates the proposal's fields, and
rechecks within its write transaction. The recipient never gains `delete`,
`create_agent`, or `create_automation` through this template. Tests verify
`delete` is refused even when the issuer already holds that action.

## 7. Enforce effects with Overlay

The CLI Overlay policy protocol is `Pass(request)` to call the host, or
`Mock(result)` to return a result without calling it. Returning
`Mock(Error(reason))` denies fallible operations. `overlay.make` builds a pure
policy from `Home` and `AllowedOrigin` facts scoped to the authenticated user.

```eyg
let {overlay} = import "../eyg_packages/authorization/index.eyg"
let db = @{
  fact Home({tenant: "acme", actor: "alice", path: "/home/alice"}),
  fact AllowedOrigin({tenant: "acme", actor: "alice", scheme: HTTPS({}), host: "api.example.com", port: None({})})
}
let policy = overlay.make(db, {tenant: "acme", actor: "alice"})
let write = {path: "/home/alice/drafts/../report", contents: !string_to_binary("report")}
!equal(policy.write_file(write), Pass({path: "/home/alice/report", contents: write.contents}))
```

The fetch rule requires `GET({})` and an exact allowed scheme, host, and port.
Read, write, append, directory listing, and directory creation require a path
under the user's home; the policy passes its normalized absolute path to the
host. Delete, key creation, and standard input are denied. Signing over supplied keys follows the CLI's deterministic-computation rules. Randomness is mocked deterministically and exit requests become failed tool runs. Environment
lookups return `None`, working-directory lookup returns `Error`, and sleep is
mocked. Clock reads and diagnostic output pass through.

Use [the sample Overlay configuration](../examples/authorization/overlay.eyg)
with `eyg overlay examples/authorization/overlay.eyg`. It reads `HOME` during
trusted startup and runs a local Ollama model. The authenticated principal is
fixed to Alice for this single-user demonstration; a service must supply its
own authenticated identity and trusted home mapping.

**This is a lexical path policy, not an OS sandbox.** The computer runtime
follows filesystem links. To enforce physical home containment, run it in a
filesystem sandbox with no link or mount escape, or use a host that opens files
relative to a confined directory descriptor. Pure rules cannot inspect these
host details. The integration tests use Loam's in-memory filesystem, which has
no links, and verify that denied writes never change it. A real deployment must
also control redirects, DNS/network routing, sensitive data in diagnostics,
and resource budgets. GET alone does not imply a remote endpoint has no side
effects. The CLI's host effect catalogue remains the outer capability boundary.

## 8. Companies, teams, agents, and long-running tasks

The [enterprise fixture](../eyg_packages/authorization/enterprise_fixture.eyg)
contains two companies, engineering and sales departments, multiple members and
projects, and two agents with separate tasks. Every relation carries a tenant.
The request also names a project; its team supplies the applicable policies.

| Company/team | Agent creation | Automation creation |
| --- | --- | --- |
| Acme / operations | Automatic for engineers | Automatic for engineers |
| Acme / sales | Requires a current project-specific approval | Denied |
| Beta / operations | Denied | Denied |

`enterprise.human` checks a human's direct, current team rights. An `automatic`
team policy needs membership and project ownership. An `approved` policy also
needs an `Approval` matching tenant, actor, project, and action. No matching
policy means denial. Its expiry is the earliest membership, policy, and
approval deadline.

```eyg
let {enterprise} = import "../eyg_packages/authorization/index.eyg"
let {db} = import "../eyg_packages/authorization/enterprise_fixture.eyg"
let sales = {tenant: "acme", actor: "carol", project: "crm", action: "create_agent", resource: "/acme/crm"}
let before = enterprise.human(db, sales, 100)
let after = enterprise.human(db, sales, 130)
let automation = enterprise.human(db, {action: "create_automation", ..sales}, 100)
!equal({before, after, automation}, {
  before: [{tenant: "acme", actor: "carol", project: "crm", action: "create_agent", resource: "/acme/crm", expires: 130, grants: ["sales-agent"]}],
  after: [], automation: []
})
```

The host handles creation as a transaction: authenticate the human, check the
current snapshot, create the agent/task record, then store admitted read/write
delegations. Creating an agent gives it no data rights by itself. An automation
launches agents through the same creation and delegation service; its scheduler
must reauthorize each launch. This tutorial implements that policy decision,
not a scheduler or a persistence service.

`enterprise.agent` additionally requires an active agent owned by the proof's
root issuer, a running task belonging to that agent and project, current
deadlines, and a delegated action whose scope includes the resource. One task's
authorization cannot be reused by another agent or project.

```eyg
let {enterprise} = import "../eyg_packages/authorization/index.eyg"
let company = import "../eyg_packages/authorization/enterprise_fixture.eyg"
let request = {tenant: "acme", actor: "a1", task: "report", project: "atlas", action: "read", resource: "/acme/atlas/reports/october"}
let before = enterprise.agent(company.db, request, 100)
let expired = enterprise.agent(company.db, request, 150)
let revoked = @{company.organization, company.policies, company.agents, company.tasks}
let after_revocation = enterprise.agent(revoked, request, 101)
!equal({before, expired, after_revocation}, {
  before: [{tenant: "acme", actor: "a1", task: "report", project: "atlas", action: "read", resource: "/acme/atlas/reports/october", expires: 150, grants: ["alice-report", "ops-read"]}],
  expired: [], after_revocation: []
})
```

An agent running for hours must authorize each effect against fresh facts and
host time. A previously returned `Permit` is audit evidence, not a bearer
credential. Cancelling a task, removing its delegation, expiring membership,
or removing a policy denies its next operation. Coordinate the decision and
effect with a transaction or a checked snapshot revision when concurrent
revocation must take effect atomically. The tests also cover mismatched owners,
cross-tenant requests, wrong projects, and attempts to change read into write.
