# Concepts

A box is a named, versioned EYG computer. Its current root is a content identifier
(CID) for a UnixFS tree. Files contain code, assets, configuration and runtime data.

## Roots, snapshots and forks

Every accepted mutation publishes one complete root. Previous roots remain
available in the box history. A fork starts an independent box at a chosen root.
Filesystem snapshots include application configuration and recorded traces.
In-flight computations and external services are outside the snapshot. Forking
does not undo a sent message or repeat an interrupted network request.

## Transactions

Submit the root you read and an ordered batch of put, mkdir and delete operations.
Authorization uses canonical absolute paths and the existing policy. All changes
are constructed privately, then all EYG modules and interface contracts are checked.
The new root is persisted before success is acknowledged. Any failure leaves the
published root unchanged. HTTP 409 means another commit won: inspect the new root,
reconcile your changes, and submit a new batch. There is no automatic merge.

The whole box has one commit owner. Agent and cron writes can conflict with API
edits even when they touch different paths. Readers capture a single root.

## Checked dependencies

Files ending in .eyg or .eyg.json are EYG modules. Relative imports resolve from
the importing file. Absolute imports resolve from the box root. Other files are
binary values. Pattern imports such as /app/assets/:{name}.txt return a sorted
list of {path, bytes}; EYG patterns return {path, source}. A capture matches one
path component. All matched items must have a consistent type.

Every module must type-check and its top level must evaluate successfully. Abort
is the only admitted top-level effect, and actually calling it rejects the commit.
Functions may return effectful computations for the runtime to execute later.
Missing imports, cyclic imports and incompatible dependency changes are rejected.

## Interfaces

/system/http.eyg is {handler, policy}. Its handler receives {method, path, headers,
body}; headers are a list of {name, value}, and body is binary. It returns
{status, headers, body}. The handler and its imports come from one committed root.

/system/cron/NAME.eyg is {cron, handler, policy}. Cron uses five-field expressions
in UTC. The handler receives {} and returns {}. Deadlines are recalculated after
configuration changes. Missed ticks are skipped rather than replayed in a burst.
An explicit Run now action does not change the automatic deadline.

Handlers run serially within their box. Each effect is policy-gated, and a policy
update cannot interleave with an active handler. Filesystem changes are checked
and published when the handler completes. External effects are immediate: a
later failure does not roll back Fetch or a message already sent. Callers should
use idempotency keys when retrying externally visible operations.

Execution records are appended beneath /traces using the same validation and
publication mechanism. A trace write is itself a new root.

## Policies and identity

Account-managed tokens are outside the box. A token belongs to one box and has a
pure EYG predicate taking {identity, box, operation, path} and returning True({})
or False({}). Identity is the token's SHA-256 identifier. Revocation is checked
on each API operation. Forking a box does not copy account grants.

Interface policies are ordinary EYG records in the box, using the existing
Pass(input)/Mock(result) effect policy protocol. Templates allow reads and restrict
filesystem writes to /data/. They allow Fetch and configured environment secrets;
edit the policy to narrow those effects for your application. Policy changes must
be authorized by the policy that was already committed.

## Layout

/system       interface and policy configuration
/app          checked application code and immutable assets
/data         runtime data
/skills       instructions for agents
/traces       execution records

The filesystem API can also use other paths. These directories are conventions,
not a second storage model. See the templates for complete initial filesystems.
