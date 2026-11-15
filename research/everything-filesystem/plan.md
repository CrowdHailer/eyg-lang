# Everything file system

EYG is a functional immutable language.
This means that there is no concept of self, a system can process data but not modify itself.
Where the concept of self is loosly defined.

One solution is to identify a computer as the concept of self.
Essentially I equate existance to a timeline of mutable state.
The computer consists as a set of processes and kernel state living on a file system. Is there anything missing that should be considered a core part of an operating system that is relevant for this discussion.

This is not the only solution for the concept of identity.
A spread sheet is another layout of mutable items that can evolve over time. Are there more?

An entity that exists (has a mutable timeline regardless of implementation) has additional properties
- Snapshot the entity at a given point in time
- Fork, evolve more than one instance forward from a snapshot.

The fact that a system has these properties does not imply that the implementation of these properties is efficient.

The file system is a long established solution to a computable system having an existence.

However the file system abstraction has downsides (we'll consider which of these are important or workable later).
- There is no standard reconsiliation approach for concurrent access.
- Unix has a built in concept of users and groups, that is not fine grained enough for all usecases.
- With everything in a file system several work arounds come into existance. One is watching for changes.

For now my goal is to create an incredibly intuitive set of primitives for build a cloud native system with an evolvable existance.
It doesn't need to handle scaling i.e. lots of concurrent actors.

Example use of the file system.

Once setup systemd is the single process that is booted as part of turning on a computer.
Configuration of what is running is set up in systemd config files. Where do these live what is the format?

Installing php (is it php or apache) is pointed at applications with a config file on the file system. What are the details here?

More recently vercel/nexjs use layout of a project on the file system to specify how an application works.

A global mutable file system is not something that is type checked programs that load data/config have to have runtime errors for any dependencies on the file system.

## EYG cloud

This is a cloud native computer

This builds upon Mutable File System (MFS) a box (is this a good name).
Is a named reference to a stream of mfs hashes.

The system is headless, i.e. it is API first

```
PUT cloud.eyg.run/:name/foo/bar
GET cloud.eyg.run/:name/foo/bar
```
headers decide if a raw blob is being uploaded or a reference to existing blobs.

Each box has a current filesystem root hash.

A mutation supplies the root hash it was based on and a candidate new root.
The candidate may create, replace, or delete multiple files and directories.

Validation runs against the complete candidate, so there are no intermediate states to be valid.

The candidate becomes the current filesystem only if validation succeeds and the supplied base hash still matches the current root at commit time. Publishing the new root is atomic: readers see either the old filesystem or the new one, never a partially applied batch.

A conflict returns the current root hash so the caller can inspect the intervening changes and submit a revised batch.
There is no automatic merging.
This is a firm decision. The conflict check is on the whole root, so a box whose handlers write often will conflict with unrelated edits; callers retry.
The server does not reapply a non-overlapping change onto a newer root.

### Commit

The one commit primitive is a base root, a new root and a CAR file holding the blocks the box does not already have.

```
POST cloud.eyg.run/:name/commits
Content-Type: application/vnd.ipld.car
Base-Root: <previous-root-hash>
New-Root: <candidate-root-hash>

<car bytes>
```

- The server verifies every block hash and that the graph under the new root is complete.
- Encoding must be canonical. Non-canonical directory blocks, blocks not reachable from the new root and oversized archives are rejected, so two clients always produce the same root for the same tree.
- Authorization is on the actual change. The server diffs the base against the new root and authorizes every path that differs, including each path under a removed directory. Equal hashes are skipped so the diff is cheap.
- Handlers, agents and other internal writers submit the same base and new root as external clients.
- The `eyg` CLI speaks CAR.

A writer restricted to a single path cannot build a new root, because that needs the directory blocks above the path and those list sibling names and hashes.
The API must also stay usable from curl.
So `PUT` of a single file and the batch operation below remain as sugar: the server builds the candidate root from them and passes it through the same commit path, so authorization and validation cannot diverge.

Batch operation

```
POST cloud.eyg.run/:name/transactions
Content-Type: application/json

{
  "base": "<previous-root-hash>",
  "changes": [
    {
      "operation": "put",
      "path": "/app/server.eyg",
      "reference": "<server-content-hash>"
    },
    {
      "operation": "put",
      "path": "/app/routes/account.eyg",
      "reference": "<route-content-hash>"
    }
  ]
}
```

The EYG cloud is not just a file system.
There is also

- Each named space has a public presence, a subdomain on eyg.cloud. It can be configured to respond to web requests to that domain.
  - Configuration should be a familiar as possible to people setting up a lamp stack, but everything is type checked and configured using EYG.
- Any EYG scripts are checked, including all the imports they rely on.
  - a file `!int_add(import "../foo.eyg", import "../bar.eyg") will prevent the file system being updated unless they type check.
- SSH can be configured so that when a user is connected the connected shell has a policy (look at the existing approach to policies) applied to any effects they execute in the shell.

This allows full applications to be built with their own collaboration rules.
Any changes to the system are checked.

For example Create a simple web service

```eyg
// /app/server.eyg
let routes = import "/app/routes/:{path}.eyg"
let images = import "/app/images/:{image}.png"

let server = (request) -> {
  // todo use the routes and images
}
```

In this example routes has type `List({path: String, source: (request) -> response})`
while images has type `List({path, bytes})`.
A valid EYG file, text or JSON source, is parsed.
If using the pattern syntax, then the result of the import is a list and each item must have consistent type.

Checking EYG code checks that it is sound, type checking passes, and that the top level evaluates without calling Abort.
Abort is the only effect allowed at the top level of a `.eyg` file.
Effects like `Fetch` are in functions that are returned by and `.eyg` file.

A user policy can prevent anyone who is not the admin from changing any files except the individual routes.
Rules could be even more precise so an agent from the accounts team can only update the `/app/routes/account.eyg` path.

Derived values can also be implemented using the imports

```eyg
// in path/home.eyg
let raw = import "page/home.md"
let page = match !string_from_binary(raw) {
  Ok(content) -> content
  Error(_) -> perform Abort("page/home.md must be UTF8")
}
page
```

Here the type of `home.eyg` is a string, not just bytes.
This can be used for much more sophisticated transformations.
i.e.

```eyg
let images = import "images/:{image}.png"
let processed = list.try_map(images, do_image_have_valid_location_metadata)
match processed {
  Ok(processed) -> processed
  Error(_) -> perform Abort("All images must have location metadata")
}
```

Importing structures that are not just eyg code is something that can be generalised.
i.e. `let signatory = #bac1234` could point at a dag_json encoded unteathered signatory.
As dag_json types can all be matched to EYG types then any dag_json imported (that is not EYG) gets imported as it's structure.

## Boot module

All configuration of external services, HTTP, SSH, cron, Slack, Discord and API tokens, is one EYG module that lives outside the file system.
It fulfils the role of PID 1 starting systemd: it is fixed from outside the computer and by default it reads the rest of the configuration from the file system.

- Only an external admin can change it, from the account dashboard. Nothing running inside the box, agent or handler, can widen its own reach.
- Its type is the interface contract, i.e. a record like `{http, cron, slack, ssh, tokens}`. There are no reserved paths in the checker; `/system/...` is only a convention used by the default module.
- It can import from the file system. The default delegates everything:

```eyg
{
  http: import "/system/http.eyg",
  cron: import "/system/cron/:{name}.eyg",
  // slack, ssh and tokens follow the same shape
}
```

- The pattern imports decide how much the box may rewire itself. Replacing an import with a fixed value takes that interface out of the box's control.
- Bindings to the outside, which Slack channel, hostname or SSH key reaches this box, and the credentials for them are in the boot module. A box cannot claim a channel by naming a file.
- It is versioned as its own stream of hashes. Behaviour is a function of the pair (root, boot module), and the pair is recorded for every invocation.
- Checking runs in both directions through the box owner. A file system commit is checked against the current boot module, and a boot module change is checked against the current root.
- A fork copies the file system but not the boot module. The fork has no connections until an admin gives it some, so two boxes never answer the same channel.
- The policy in the boot module is a ceiling, not a default. The external gate runs first and then the policy from the file system, so the effect allowed is the intersection.
- It supervises. Handlers, cron jobs, shells and agent turns run as children against a captured root, outside the box owner, and submit their writes as ordinary commits.

Connections to the outside are the environment of the box, they are not part of its self.

Open question: are only modules reachable from the boot module checked, or every `.eyg` file as stated above?
Reachable only would stop a stray file in `/data` blocking a commit.

## Journal

Logs live outside the file system. The journal is to the boot module as journald is to systemd.

- An invocation that only reads does not create a new root. A request cannot invalidate somebody else's commit just by being served.
- Each entry records the root and boot module version the invocation ran against. Rejected commits are recorded as well.
- The journal does not fork or roll back with the file system. It records what happened in the world, which cannot be undone.
- An agent cannot edit its own audit trail.
- Programs cannot read the journal to begin with; it is available to the admin through the API and dashboard.
- When a program needs it, add an effect that queries the journal by interface and time range. It is not a read only path in the file system: that would bring back a reserved path and make `ReadFile` no longer a function of the root.

## Durable scripts

Any scripts that trigger as part of an HTTP request live outside the file system.

## Overlay agent

Connecting to a box can be configured to return a shell, or an overlay agent session.
This configuration is all specified on the file system as well.

A user who logs into the cloud website can try an connect to a box

## External agents

A API token can be issued for the API that is restricted, again using a policy that can express anything because it is a full EYG script.
This means you can give an agent specific permissions and it works from the outside.

Creating a policy is something that is done from an account dashboard outside the box.
This is because the box does not issue it's own tokens to the direct modify file system API.

There is one policy system. A token grant is expressed with the same effect policy as an interface, it is not a separate predicate language, and grants live in the boot module.
A token that can connect gets the intersection of its own grant and the connection's policy, never the union.

Policies for HTTP requests, SSH sessions, and agent connections are defined in the boot module, which by default delegates to the filesystem configuration for each interface. The boot module's own policy is the ceiling for anything delegated. Permission to modify the delegated configuration controls who can change the interface’s policy below that ceiling.
Changes are authorized using the policy and its dependencies from the currently committed filesystem, before applying the proposed changes. A policy introduced by a transaction cannot authorize that same transaction.
Sessions retain their authenticated identity, but each effect is authorized using the current committed policy for that connection. Filesystem write authorization is checked as part of committing the transaction.

## Connections

Instead of just exposing a port, for webhooks, There are direct slack/discord connections.
The boot module binds a slack channel to the box. By default it routes to files in the box that configure what to do on incoming slack messages.

## Web interface

The website will be built using etui on howdy. As started on the howdy branch
It will have the same interface as sshing into the cloud service, although we aren't implementing that now.

The homepage is a neat full screen tui that allows you to setup a box.
In few operations a user should be able to set up a box and create rules for an agent in a slack channel that can only modify files in `/slack/channel/id` but it can read `app/skills` so that it can load app specific skills.

Every agent trajectory trace is saved, but it is split in two.
The append only trace of what the agent did goes to the journal.
The conversation memory the agent needs for its next turn is ordinary data in the file system, so a fork carries its memory with it.

Each box has a single owner process that serializes commits. Multiple clients and agent sessions can still propose changes based on the same root. The expected-root check prevents a stale proposal from silently overwriting a newer commit.
The owner only checks and publishes. It never runs a handler, a shell or an agent turn.

Agent memory writes and other system-generated filesystem changes follow the same commit rules.

## Checking and storage

- Evaluating the top level of a module has a budget and happens in a process that can be killed. A module that does not terminate rejects the commit, it does not hang the box.
- A relative import resolves to the hash of the file and is checked once as a content reference. Source is not inlined into each importer. Only modules whose transitive hash changed are checked again.
- A snapshot is self contained. The content of every pinned package a root depends on is stored with the box, so a box starts without the hub.
- A box that fails to start does not stop the other boxes from starting.
- Open question: the example above gives `{path, bytes}` for a `:{image}` capture. Is `path` the full path or the captured segment, and should the field take the capture's name?
- There is one tenant and one admin for now. Bindings and credentials being in the boot module is what keeps that safe to extend later.

## Review of the first implementation

The two sections after this one were written with the first implementation and describe it, not the design above.
A review on 2026-11-15 found the following differences. The test suite was not run as part of that review.

- [ ] Add the boot module. Remove the reserved `/system/...` paths from the checker and the routing of channels by file name.
- [ ] Move traces to the journal. Every HTTP request and cron run currently writes `/traces/...` as a new root.
- [ ] Run handlers, cron jobs, shells and agent turns outside the box owner. A handler that sleeps or fetches currently blocks every read and commit, and the public HTTP route is unauthenticated.
- [ ] Bound top level evaluation.
- [ ] Resolve imports by content reference instead of inlining source, and stop checking the whole tree on every commit.
- [ ] Replace the token predicate over `{identity, box, operation, path}` with the effect policy, composed as an intersection.
- [ ] Store pinned package content with the box and isolate a box that fails to start.
- [ ] Add the CAR commit and put `PUT` and the batch operation on top of it. This replaces the separate block upload and `reference`.
- [ ] Split the agent trace from agent memory.
- [ ] Durable scripts are not implemented.
- [ ] The dashboard is HTML forms with an etui summary panel, not the full screen tui described above.
- [ ] Decide whether the twenty templates, the docs pages, the Playwright demo and the 3.5 MB recording in git belong on this branch. None were in the plan.
- [ ] The earlier session and trigger runtime still runs alongside the box runtime. Migrate or remove it.
- [ ] Record the trade-offs that remain in `notes`, as AGENTS.md asks.

Kept from the first implementation because they are good decisions:

- A moving `@name` reference is rejected in a box.
- Authorization uses the committed policy and is checked again at publication.
- Paths are made canonical before authorization.
- One connection configuration per channel maps an identity to a policy.
- Interface contracts are type checked at commit.
- Recovery verifies hashes, link sizes and historical roots, and fails instead of starting empty.
- Missed cron ticks are skipped, and external effects are documented as not rolled back.

## Implementation and verification

The implementation is in `packages/cloud`. Start the web runtime with
`gleam run -m cloud/web`; its README describes configuration and the browser test.

- The box owner constructs, checks and durably publishes complete candidate roots.
- HTTP, UTC cron, shell/Overlay connections and Slack/Discord routing are configured
  by files. Account-issued API grants are persisted outside the box.
- The Howdy/etui dashboard includes filesystem transactions, webhook/cron setup,
  channel-scoped agent policies, token management and snapshot forks.
- Concepts, API reference, getting started, and all files from twenty distinct
  templates are accessible from the dashboard navigation.
- `demo/webhook-and-cron.webm` records the real dashboard workflow. The browser
  test also checks an external HTTP request and an automatic cron tick.

The initial implementation deliberately validates the whole tree and stores all
historical blocks in a per-box snapshot file. This keeps the low-concurrency
model explicit. Active executions are outside filesystem snapshots; external
effects cannot be rolled back by restoring a root. SSH transport remains deferred
as stated above; the web connection uses the same shell/agent and policy model.

## Follow-on implementation steps

This is a finite follow-on pass after the initial commit review and recording:

- [x] Make dependency execution reproducible and policy-safe: enforce connection
  read policies on imports, freeze package references before execution, and check
  authorization again at the publication boundary.
- [x] Complete content-addressed API ergonomics: upload reusable blocks, resolve
  non-EYG DAG-JSON structures by CID, and support the short filesystem routes
  shown at the beginning of this plan alongside the documented `/api` routes.
- [x] Strengthen storage recovery: sync publication metadata, reject incomplete
  or corrupt block graphs, and verify recovery and content-reference workflows.

The follow-on pass is implemented and covered by the cloud test suite. Package
references must be versioned or fully pinned so restarting a snapshot cannot
silently select a newer release. The content-data representations and recovery
contract are documented in the concepts guide.

Completion verification (2026-11-15): formatting and warnings-as-errors builds
pass; all 26 cloud tests pass, including all twenty templates, recovery,
authorization, content imports, and simulated channel/model integration. The
browser workflow also passes against the final server with a real HTTP request
and automatic cron tick. Live Slack/Discord/model accounts were not used for the
recording. The implementation commits were reviewed in order; subsequent commits
extend the same primitives rather than replacing a discarded implementation.
