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

A mutation supplies the root hash it was based on and a batch of filesystem changes.
The batch may create, replace, or delete multiple files and directories.

Validation runs against the complete candidate, so intermediate states within a batch do not need to be valid.

The candidate becomes the current filesystem only if validation succeeds and the supplied base hash still matches the current root at commit time. Publishing the new root is atomic: readers see either the old filesystem or the new one, never a partially applied batch.

A conflict returns the current root hash so the caller can inspect the intervening changes and submit a revised batch.
There is no automatic merging.

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

Policies for HTTP requests, SSH sessions, and agent connections are defined in the filesystem configuration for each interface. Permission to modify that configuration controls who can change the interface’s policy.
Changes are authorized using the policy and its dependencies from the currently committed filesystem, before applying the proposed changes. A policy introduced by a transaction cannot authorize that same transaction.
Sessions retain their authenticated identity, but each effect is authorized using the current committed policy for that connection. Filesystem write authorization is checked as part of committing the transaction.

## Connections

Instead of just exposing a port, for webhooks, There are direct slack/discord connections.
Files in the box configure what to do on incoming slack messages.

## Web interface

The website will be built using etui on howdy. As started on the howdy branch
It will have the same interface as sshing into the cloud service, although we aren't implementing that now.

The homepage is a neat full screen tui that allows you to setup a box.
In few operations a user should be able to set up a box and create rules for an agent in a slack channel that can only modify files in `/slack/channel/id` but it can read `app/skills` so that it can load app specific skills.

Every agent trajectory trace is saved into the file system as well.
Each box has a single owner process that serializes commits. Multiple clients and agent sessions can still propose changes based on the same root. The expected-root check prevents a stale proposal from silently overwriting a newer commit.

Agent trace writes and other system-generated filesystem changes follow the same commit rules.

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
- [ ] Strengthen storage recovery: sync publication metadata, reject incomplete
  or corrupt block graphs, and verify recovery and content-reference workflows.
