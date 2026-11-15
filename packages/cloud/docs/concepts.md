# Concepts

A box is a named, versioned EYG computer. Its current root is a content identifier
(CID) for a UnixFS tree. Files contain code, assets, configuration and runtime data.

## Familiar configuration, checked before activation

On Linux, systemd typically reads administrator unit files from /etc/systemd/system
and packaged units from /usr/lib/systemd/system (sometimes /lib/systemd/system).
Units use sections such as [Service] with directives such as ExecStart. Apache
similarly reads site configuration under /etc/apache2 or /etc/httpd; PHP commonly
runs through PHP-FPM, whose pool configuration is separate from Apache's routing.

The box uses the same idea of filesystem-defined behavior, with EYG records and
functions instead of separate configuration languages. Its application entry
points are checked before activation. Network connections, in-flight requests and
host-managed credentials are runtime capabilities outside the persisted tree.
This is a cloud computer abstraction, rather than a POSIX or FUSE filesystem.

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

Use versioned or fully pinned package references in boxes. A moving @name is
rejected because the same snapshot could otherwise change meaning on restart.
Version references are resolved before execution and closures retain content IDs.
Shell imports obey the connection's read policy, including nested imports.

## Content blocks and DAG-JSON

Upload a block independently, then reference its CID in a transaction or in EYG.
Raw blocks import as binary. DAG-JSON blocks containing EYG IR import as code;
other DAG-JSON imports as data: objects become records, integers and strings
retain their types, booleans become True/False, bytes become binary, null becomes
Null({}), and links become Link("CID"). Links are values rather than implicit I/O.

Uniform arrays become lists. Heterogeneous arrays use indexed variants Item0,
Item1, etc., preserving order and each element's type without an unsafe dynamic
value. Non-integer numbers become Number("decimal representation"), since EYG
has no native floating-point value. These representations make every supported
DAG-JSON data shape expressible without changing the language's IR.

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

## Recovery

Snapshot publication syncs the temporary file, atomically renames it, and syncs
its parent directory before acknowledgement. Unpublished temporary files are
ignored on restart. Recovery checks every content hash, directory name, linked
block size and historical root; missing or corrupt graphs fail to load rather
than silently becoming an empty computer. Run one service instance per data
directory. An interrupted request may have committed before its response was
lost; inspect the current root before retrying it.

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
