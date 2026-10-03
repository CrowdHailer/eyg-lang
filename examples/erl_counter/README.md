# Erlang counters, scripted with EYG

An OTP application with dynamically supervised counters. Each counter starts at
zero and increments every ten seconds. All application code and tests are Erlang;
Gleam builds the existing EYG libraries for the Erlang target.

[Watch the remote-shell demo](video/erl-counter.mp4): start the application, type
a script using `@standard`, check it with automatic dependency loading, and run it.
[Recording instructions and local player](video/README.md).

## Build and start

Requires Erlang/OTP 28 (the version used to test this example) and Gleam.
Run these commands from `examples/erl_counter`:

```sh
gleam build --warnings-as-errors
erl -sname counters -pa build/dev/erlang/*/ebin \
  -eval '{ok, _} = application:ensure_all_started(erl_counter).'
```

The caller creates and owns the package cache. Both `check` and `run` fetch missing
package references automatically and return `{Result, Cache}`. Pass the returned
cache to the next call. Scripts using only the counter effects need no network
requests:

```erlang
Cache0 = eyg@hub@cache:empty().
{{ok, _Type}, Cache1} = counters_eyg:check("perform StartCounter(\"apples\")", Cache0).
{{ok, _Started}, Cache2} = counters_eyg:run("perform StartCounter(\"apples\")", Cache1).
{{ok, _Rate}, Cache3} = counters_eyg:run("perform SetTickRate({name: \"apples\", seconds: 1})", Cache2).
{{ok, _Value}, Cache4} = counters_eyg:run("perform GetValue(\"apples\")", Cache3).
{{ok, _Stopped}, Cache5} = counters_eyg:run("perform Shutdown(\"apples\")", Cache4).
```

`check/2` returns `{{ok, Type}, Cache}` or `{{error, Message}, Cache}`. `run/2`
returns `{{ok, Value}, Cache}` or `{{error, Message}, Cache}`. Both accept Erlang
strings or UTF-8 binaries and leave printing to the caller. The one-argument
conveniences start with an empty cache, print the result or diagnostic, and return
the same `{Result, Cache}` shape. They do not reuse previous calls implicitly.

| Effect | Argument | Reply |
| --- | --- | --- |
| `StartCounter` | `String` | `Result({}, String)` |
| `SetTickRate` | `{name: String, seconds: Integer}` | `Result({}, String)` |
| `GetValue` | `String` | `Result(Integer, String)` |
| `Shutdown` | `String` | `Result({}, String)` |

The types and handlers are in [`src/counters_effects.erl`](src/counters_effects.erl).
The direct Erlang API is `counters_api:start_counter/1`, `set_tick_rate/2`,
`get_value/1`, and `shutdown/1`. Names are binaries. Tick intervals are positive
integer seconds. Duplicate names, missing counters, and invalid intervals become
EYG `Error(...)` values, rather than interpreter failures.

## Use packages referenced by the script

Package loading is driven by the script's references. There is no preconfigured
package list or special treatment of `standard`. For example, in the Erlang shell:

```erlang
{{ok, _ListType}, Packages1} = counters_eyg:check(
    "@standard.list.map([1, 2], (x) -> { x })", eyg@hub@cache:empty()
).
{{ok, _Results}, Packages2} = counters_eyg:run("
  @standard.list.map([\"a\", \"b\", \"c\"], (name) -> {
    let _ = perform StartCounter(name)
    perform SetTickRate({name: name, seconds: 1})
  })
", Packages1).
```

The `check` call fetches `standard` and returns it in `Packages1` without performing
any counter effects. The following `run` reuses that cache and returns `Packages2`.
Calling `run` first works too: it loads its own missing references before checking
or executing the script.

The default hub is `https://eyg.run`. To select another origin before loading:

```erlang
application:set_env(erl_counter, hub, <<"http://localhost:8001">>).
```

[`src/counters_packages.erl`](src/counters_packages.erl) uses existing Gleam
packages, called directly from Erlang:

1. After parsing, `list_references/1` identifies the script's references. If all
   are already cached, loading completes without HTTP.
2. `eyg@hub@cache:prepare/2` queues content/pinned modules and any necessary
   release-ledger pull. `flush/1`, `compute/4`, and `update/3` process these actions.
3. With the ledger available, `package/2` and `unbound_release/3` resolve names
   and versions to their module CIDs. Pins must match the ledger.
4. `fetch/2` queues those modules. The same action loop fetches their immutable
   dependencies and evaluates their module values.
5. Each module response goes through `eyg@hub@client:fetch_module/4`, which
   decodes the IR and checks its computed CID against the requested CID.
6. The loader checks every downloaded module's types with its dependencies
   available before returning the cache. This is an explicit step because the
   existing cache infers types but does not itself reject inference errors.

`gleam@httpc:send_bits/1` supplies HTTP, and `gleam@crypto:hash/2` supplies hashing.
The hub's continuation callbacks are ordinary Erlang functions: `Task(K)` runs
work and passes its result to `K`. `Task(fun(Result) -> Result end)` obtains the
result synchronously.

The optional `erl_counter` application setting `package_fetch` overrides the HTTP
callback with a function of the same continuation shape. The tests use this to
exercise `check` and `run` against deterministic hub responses.

An empty action queue means there is no work left; the loader also checks fetch
failures, module evaluation failures, and final reference availability. It does
not treat an idle cache alone as success.

### Keep the cache in application state

Every call returns the cache explicitly, on success and on errors. There is no
hidden global cache. An application can keep it in a `gen_server` state map:

```erlang
%% In the host's gen_server; initialise state.cache with eyg@hub@cache:empty().
handle_call({check, Source}, _From, State = #{cache := Cache0}) ->
    {Result, Cache1} = counters_eyg:check(Source, Cache0),
    {reply, Result, State#{cache := Cache1}};
handle_call({run, Source}, _From, State = #{cache := Cache0}) ->
    {Result, Cache1} = counters_eyg:run(Source, Cache0),
    {reply, Result, State#{cache := Cache1}}.
```

[`counters_session`](src/counters_session.erl) implements this ownership pattern
and is used in the video. For an interactive remote shell, keep the large cache
in that process and return just the result to the shell:

```erlang
{ok, Session} = counters_session:start_link().
{ok, Type} = counters_session:check(Session, Script).
{ok, Value} = counters_session:run(Session, Script).
```

Keep the returned cache even when `Result` is an error:

- Parse errors return the supplied cache unchanged.
- Failed fetching or package validation returns the supplied cache unchanged;
  that failed batch is not exposed as reusable modules.
- Once loading and module validation succeed, script type errors and runtime
  failures return the loaded cache, so the next call can reuse those packages.

Each operation uses the same completed cache snapshot for checking and execution.
The host decides how long to retain that cache and which calls share it.

This follows the CLI execution runtime's explicit result/state threading model
(`loam.execute.State` contains its cache). The CLI's current `check` implementation
does not resolve hub references; this example supports them in both APIs.

Cached names use the latest release known to that cache; they are not polled for
updates on each call. To start a single operation with a fresh cache, pass an
empty cache explicitly; its references determine what gets loaded:

```erlang
counters_eyg:check("@json", eyg@hub@cache:empty()).
```

A script can refer to several packages. The loader reads their release mappings
from the hub and fetches only the referenced modules and their dependencies;
other packages appearing in the release ledger are not automatically downloaded.

Automatic loading supports content references (`#cid`), names (`@standard`),
versions (`@standard:1`), and pins (`@standard:1:cid`), including fetching historical
release modules on demand. A pin must agree with the ledger. Content-only
references do not require a ledger pull unless their dependencies need one.
Relative file imports are not resolved by this example.

## How `run` and `run_step` work

The implementation is in [`src/counters_eyg.erl`](src/counters_eyg.erl).
Once loading has produced a cache, there are two distinct uses for each cached
module: its **type** during checking and its **value** during execution.

### `run`: check the complete script, then begin evaluation

Both `run` entry points use the same pipeline, starting from the caller's cache
(`run/2`) or an empty cache (`run/1`):

1. Parses the whole source into an annotated IR tree.
2. Loads missing references and their dependencies. A fetch, CID, or module
   validation failure returns an error before any counter effect executes.
3. Creates a pure inference context, then adds exactly the four counter effects.
4. Calls the typechecker. `cache.infer_sync` answers every reference lookup with
   the cached module's polymorphic type.
5. Collects all type errors. Any error returns a source-positioned diagnostic
   before a counter handler can run.
6. On success, calls `expression.execute(Tree, [])` and passes its result to
    `run_step`.
7. Returns the execution result alongside the loaded cache.

The empty list is the lexical scope. Packages are resolved through references,
not inserted as lexical variables. `check` performs the same parsing, loading,
and inference steps, then returns the inferred type and cache without executing the script.
Malformed source fails before loading starts.

### `run_step`: resolve references, handle one effect, resume

The interpreter runs until it finishes or reaches a break. A break carries
`{Reason, Span, Env, K}`: the reason, source location, environment, and remaining
computation (continuation stack).

First, `cache.static_loop` consumes reference breaks. For an available reference
it retrieves the cached value and calls `expression.resume(Value, Env, K)`.
It repeats until execution finishes or reaches a different break.

`run_step` then handles three outcomes:

- **`{ok, Value}`:** evaluation is finished; return the value.
- **`UnhandledEffect(Label, Lift)`:** dispatch to `counters_effects:handle/2`,
  receive an EYG reply value, and call `expression.resume(Reply, Env, K)`.
  Tail-call `run_step` with the new result.
- **Another break:** render a runtime diagnostic at the recorded source span.

For example:

```eyg
let _ = perform StartCounter("first")
@standard.list.map(["a", "b"], (name) -> {
  perform StartCounter(name)
})
```

The standard library is loaded and the complete script is checked first.
Evaluation stops at `StartCounter("first")`;
Erlang starts that counter and resumes with `Ok({})`. Evaluation next stops at
`@standard`; `static_loop` supplies the cached library value. The library calls
the EYG lambda twice, so `run_step` handles and resumes two more effects. The final
value is `[Ok({}), Ok({})]`.

Resuming continues after the effect; it does not restart the script or repeat
previous effects. The same reference-resolution step runs after every effect,
because a later expression can introduce another package reference. `Env` and `K`
are passed back unchanged; the host never needs to interpret their internals.

Both `check` and `run` may make network requests during their package-loading
phase. Once evaluation begins, `run_step` uses the completed cache and performs
no fetching. Typechecking prevents ill-typed scripts from starting, but execution
is not transactional: a later runtime failure does not undo already completed
counter operations.

## Inspect the application

```erlang
supervisor:which_children(counters_sup).
observer:start().
```

Observer's Applications tab shows the dynamic children under `counters_sup`.
The counter state includes its name, value, interval, and current timer reference.
To attach another Erlang shell, use the same Erlang cookie and the actual node
name returned by `node()`:

```sh
erl -sname counter_shell -remsh counters@YOUR_HOST
```

## Tests

From `examples/erl_counter`:

```sh
gleam build --warnings-as-errors
erl -pa build/dev/erlang/*/ebin -noshell \
  -s erl_counter_test main -s init stop
```

The tests are all Erlang/EUnit and run offline. They exercise actual EYG parsing,
inference, interpretation, and hub codecs. The standard-library fixture is the
repository's `eyg_packages/standard/index.eyg.json`, served by a deterministic
fetch callback. Coverage includes automatic loading through both public entry
points, explicit cache reuse and isolation between callers, caches returned on
parse/type/runtime/load errors, no requests for local or malformed code, effects before and
after reference lookup, no effects on failed fetches or checks, counter timers and
shutdown, paginated release lookup, transitive dependencies, historical versions,
pins, bad CIDs, fetch failures, and invalid package modules. A separate fixture
checks multiple arbitrary package names and verifies that an unreferenced
`standard` release is not downloaded.
