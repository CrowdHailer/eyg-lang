# Ash support

Add EYG as a scripting language that can be used within the Ash framework

- homepage https://ash-hq.org/
- documentation https://ash.hexdocs.pm/readme.html

There is an existing ash_lua package that embeds Lua as a scripting language in Ash. https://ash-lua.hexdocs.pm/readme.html
We will follow the projects structure for components we need, however we will not need the same components.

Tasks:

- [ ] install the latest Elixir and erlang
- [x] create an example erlang application in `examples/erl_counter`. It has a dynamic supervisor for counters that tick every 10 seconds
  - [x] Create functions to `start_counter`, `set_tick_rate`, `get_value`, `shutdown`
  - [x] Create an EYG effect for each of these. write the type and implementation in erlang.
  - [x] Write `counters_eyg:check/2` and `run/2`: automatically load references, typecheck against the application effects, and return `{Result, Cache}` for the application to retain. Format source-positioned diagnostics.
  - [x] Record starting the application, connecting a remote shell, typing an `@standard` script, silently loading the dependency during check, and running it with the retained cache. See [video](examples/erl_counter/video/erl-counter.mp4).
  - [ ] Create a video of joining the cluster and writing eyg scripts and executing them. Show that opening the obsever shows the new counter children and you can inspect there shape
    - first script, very simple single effect
    - second script, multiple effects
    - use the std library and create many effects
  - [ ] Write a blog post about embedding EYG in an erlang program, include the video
- [ ] Create the same counter example in Elixir, but in a phoenix application
  - [ ] There should be a script box on the homepage
  - [ ] The script box uses the textmate syntax highlighting
  - [ ] Use live view
      - [ ] Any program that parses has it's types checked, show errors on the page
      - [ ] Press enter or click submit to send the messages
  - [ ] create the same video of scripts and effects in this application
  - [ ] Write a blog post about embedding EYG in an Elixir program, include the video
- [ ] Create a package in this repo called ash_eyg
  - [ ] Implement The automatic creation of EYG effects from Ash constructs in the same way as for ash_lua
  - [ ] Show how to add just some of the effects to a eyg execution environment
  - [ ] Create a standard getting started ash project and show how to set up EYG to access the first domains and resources
  - [ ] Review and simplify the ash_eyg package
  - [ ] Create a video of setting up the project and installing EYG
  - [ ] Write a blog post about how to use EYG in Ash, be super focused on the technical steps

## Implementation decisions and learnings (2026-10-03)

These decisions supersede the `eyg_beam` approach in
[ash...1c4371ea88e31fd4daeda17a4798de034233bdea](https://github.com/CrowdHailer/eyg-lang/compare/ash...1c4371ea88e31fd4daeda17a4798de034233bdea).
Use them when implementing the remaining Elixir/Phoenix/Ash work or recreating the Erlang example.

### Scope and package boundaries

- The example lives at **`examples/erl_counter`**. All application code and tests are Erlang.
- Use Gleam as the build tool to compile the existing libraries for Erlang, with local path dependencies and a committed generated `manifest.toml`.
- **Do not introduce `eyg_beam`.** The reviewed implementation was mostly an adapter around existing public APIs. Its additional `Package(type, value)` container duplicated `eyg_hub.cache.Module`, while only resolving bare package names and dependency-free JSON files.
- Keep application-specific composition in `counters_eyg`, effect signatures/handlers in `counters_effects`, and the small host loading loop in `counters_packages`.
- Fetch packages from the hub through existing Gleam packages called from Erlang. Neither the EYG CLI executable nor a separate Gleam application-code layer is necessary.
- Do not add CLI/runtime effects for package fetching. HTTP and hashing here are host operations, separate from the effects scripts are allowed to perform.
- Keep implementation files, recordings, and artifacts in the project. **Do not put them in `/tmp`.** Recording tools/dependencies can live under the example's ignored `build` directory.

### Reuse the existing APIs

| Responsibility | Existing module/API |
| --- | --- |
| Parse the complete input | `eyg/parser.all_from_string` |
| Establish the effect whitelist | `eyg/analysis/inference/levels_j/contextual.pure` + `with_effects` |
| Typecheck and find errors | `contextual.check`, `all_errors`, `type_` |
| Resolve reference types | `eyg/hub/cache.infer_sync` |
| Execute/resume expressions | `eyg/interpreter/expression.execute`, `resume` |
| Resolve reference values | `eyg/hub/cache.static_loop` |
| Store evaluated modules and their types | `eyg/hub/cache.Module` |
| Construct record/union/result types | `eyg/analysis/type_/isomorphic` |
| Render type diagnostics | `eyg/analysis/type_/binding/debug` + `eyg/parser.render_error` |
| Render values/runtime diagnostics | `eyg/interpreter/simple_debug` |
| Hub requests, decoding, CID checks | `eyg/hub/client` |
| HTTP and hashing on Erlang | `gleam_httpc`, `gleam_crypto` |

Gleam modules use `@` in generated Erlang module names, e.g. `eyg@hub@cache`.
Gleam strings are UTF-8 binaries, dictionaries are Erlang maps, results are `{ok, Value}` / `{error, Reason}`, and constructors are atoms or tagged tuples.
EYG values retain their own tags, e.g. `{integer, 1}`, `{string, <<"a">>}`, `{record, #{}}`, and `{tagged, <<"Ok">>, Value}`.
An EYG unit **type** is `{record, empty}`; its unit **value** is `{record, #{}}`.

### Required public contract: explicit cache ownership

Both operations must accept and return a cache:

```erlang
Cache0 = eyg@hub@cache:empty(),
{CheckResult, Cache1} = counters_eyg:check(Source, Cache0),
{RunResult, Cache2} = counters_eyg:run(Source, Cache1).
```

- Return **`{Result, Cache}` on both success and failure**.
- For checking, `Result` is `{ok, TypeText}` or `{error, DiagnosticText}`.
- For execution, `Result` is `{ok, EygValue}` or `{error, DiagnosticText}`.
- The two-argument APIs leave printing to the caller. The one-argument shell conveniences start with an empty cache, print the result/diagnostic, and also return `{Result, Cache}`.
- **No hidden `persistent_term` cache.** An earlier version had one; it was removed so the host controls sharing, lifetime, and subsequent calls.
- Parse failures return the supplied cache unchanged.
- A fetching or package-validation failure returns the supplied cache unchanged: the incomplete/unvalidated batch is not exposed as reusable modules. Previously cached modules remain usable.
- Once package loading and validation succeed, return that loaded cache even when the script subsequently fails typechecking or execution. A corrected script should not need to download those packages again.
- A call uses one completed cache snapshot for both inference and execution.

The host should retain the returned cache in its application process state. The implemented
[`counters_session`](examples/erl_counter/src/counters_session.erl) demonstrates this with a `gen_server`:

```erlang
handle_call({check, Source}, _From, Cache0) ->
    {Result, Cache1} = counters_eyg:check(Source, Cache0),
    {reply, Result, Cache1};
handle_call({run, Source}, _From, Cache0) ->
    {Result, Cache1} = counters_eyg:run(Source, Cache0),
    {reply, Result, Cache1}.
```

This is a caller-owned session, not an implicit singleton. It stores cache updates on error results too.
For Phoenix/LiveView, preserve the same ownership contract; decide which application process owns the interpreter cache rather than copying it through presentation-layer state unnecessarily.

### Automatic, reference-driven loading

- **Both `check` and `run` fetch missing packages automatically.** There must be no prerequisite preload/install call.
- **Never hardcode `standard` or a list of packages.** `@standard` is just an example in scripts. The old `load_packages/0` helper that explicitly fetched it was removed, along with redundant name-preload helpers.
- Parse first, collect the IR's actual references, and load the modules needed by those references and their dependencies. Malformed input must not trigger HTTP.
- Scripts without references, or with all required references cached, need no network requests.
- Support content references (`#cid`), bare names (`@name`), versions (`@name:version`), and full pins (`@name:version:cid`), including fetching historical releases when referenced.
- A bare name resolves to the latest release known to the supplied cache. The example does not poll for updates on every cached lookup. A fresh cache starts a fresh resolution. This is a policy choice, not a claim of identical CLI freshness behaviour.
- Pins must agree with the hub's release mapping. Content references need no ledger pull unless their dependencies require one.
- Relative file imports are not implemented by this example. Do not silently imply full CLI filesystem resolution support.
- Reading the release ledger does **not** mean downloading every package listed in it.
- Default to `https://eyg.run`; the host can configure the origin using the `erl_counter` application's `hub` setting.

Loading algorithm and existing cache affordances:

1. Use `tree.list_references` to identify references. Reuse an already sufficient cache immediately.
2. `cache.prepare` queues content/pinned CIDs and any needed ledger pull.
3. Drive `cache.flush` → `cache.compute` → `cache.update` until idle. Ledger pulls continue page by page until an empty page.
4. **Important gap:** `cache.prepare` does not queue modules for bare names or version references once their ledger mappings are known. Explicitly resolve them with `cache.package` / `cache.unbound_release`, then queue their CIDs using `cache.fetch` and drain again.
5. The existing cache resolves immutable transitive dependencies and resumes dependent module evaluation. Check failures and final reference availability; an empty action list alone is not success.
6. Map downloaded IR annotations to `{0, 0}` for use alongside locally parsed source spans. This denotes unavailable source locations for downloaded IR.
7. Validate downloaded modules with all dependencies available before returning a reusable cache.

The existing cache infers a stored module's type but **does not reject `all_errors`**.
A closure with an invalid body can evaluate successfully and be cached. Keep the explicit pure inference/error check in the host loader until this is addressed in the library.
Module evaluation during loading handles no application effects; impure modules fail instead of starting counters.

`cache.compute` uses `client.fetch_module`, which decodes the IR, recomputes the module CID, and compares it with the requested CID.
Calling only `fetch_module_response` would omit the CID check. Do not describe CID validation as verification of ledger signatures.

The hub uses `midas` continuations: an Erlang callback returns `fun(K) -> K(Result) end`.
Use `gleam@httpc:send_bits/1` for binary requests/responses and `gleam@crypto:hash/2` for hashing.
Map transport errors to the hub's `{network_error, Text}` shape. Resolve a task synchronously with `Task(fun(Result) -> Result end)`.
The optional `package_fetch` application setting supplies a compatible callback for deterministic tests.

### Execution and effects

The pipeline is **parse → load references → validate packages → check the complete script → execute** (`run` only).

- Start inference from `pure()`, then permit exactly the host's effect signatures. Do not use an unrestricted effect context for this example.
- During checking, `cache.infer_sync` answers reference lookups with cached polymorphic types.
- A script's type errors must prevent **all** of its application effects, including effects appearing earlier in the source than the error.
- `expression.execute(Tree, [])` starts with an empty lexical scope. Package references are resolved separately, not inserted as lexical variables.
- In `run_step`, first call `cache.static_loop` to consume reference breaks using cached values and `expression.resume`.
- On `UnhandledEffect(Label, Lift)`, call the Erlang handler, then resume with its EYG reply and the unchanged `Env` and continuation stack `K`.
- Re-enter reference resolution after every handled effect: later expressions can introduce another reference.
- Resuming continues at the break; it does not restart the program or repeat previous effects.
- Return the final value, or format other interpreter breaks as source-positioned runtime diagnostics.
- Once script evaluation begins, `run_step` does not fetch. All needed module loading was completed before checking/execution.
- Execution is not transactional: a later runtime failure does not undo prior counter effects.

Counter implementation choices:

- Dynamic `one_for_one` supervisor; counter names are binary child IDs, not dynamically created atoms.
- Default interval is ten seconds; rate changes accept positive integer seconds.
- Match timer references in `{timeout, Ref, tick}` so a cancelled-but-already-queued old tick is ignored.
- Shutdown terminates and removes the child specification so the same name can be started again.
- Domain failures such as duplicate/missing counters or invalid intervals are EYG `Error(...)` values. They are distinct from the outer interpreter `{error, Diagnostic}` result.
- Keep effect signatures and implementations together; Erlang handlers must return the declared EYG value shape.

### CLI comparison: be precise

- `packages/loam/src/loam/execute.gleam` returns the result alongside a `State` containing the cache. Use this explicit state-threading model for embedding.
- Its reference dispatch distinguishes content, names, versions, pins, and relative imports. No standard package is implicitly special.
- At the time of this work, `packages/gleam_cli/src/eyg/cli/check.gleam` rejects hub reference lookups and resolves relative source imports. Do not claim that CLI `check` already has the example's automatic hub loading.
- The CLI execution path pulls the ledger for bare-name lookup; the example reuses known cached mappings. Full behavioural parity would require an explicit freshness decision, in addition to filesystem resolution.

### Runtime and distribution findings

- Tested on Erlang/OTP 28 and Gleam 1.18.1. Existing EYG libraries compiled for Erlang without an `eyg_beam` runtime.
- A `target = "javascript"` default in a dependency does not prevent a Gleam-managed Erlang build from compiling its Gleam sources for Erlang.
- Inspected Hex archives for `eyg_analysis` and `eyg_interpreter` contained Gleam sources but no generated Erlang/rebar packaging. Direct rebar3/Mix distribution remains a separate follow-up: publish Erlang artifacts from the existing packages rather than inventing a new adapter package.
- Carry over the reviewed commit range's diagnostic fix: `TypeMismatch` arguments are **given, expected**. Regression-test `StartCounter(1)` / `GetValue(3)` reporting `given: Integer expected: String`.
- Erlang EYG integers use arbitrary-precision bignums. JavaScript's safe-integer limit is not an Erlang overflow boundary. A runtime-error regression cannot rely on `9007199254740991 + 42` failing on Erlang.

Possible future affordances, **not requirements to add a new package now**:

- Stable short `eyg/analysis` checking/formatting entry points rather than exposing the inference algorithm's module path to hosts.
- An optional callback-driven interpreter handler loop, retaining the low-level execute/resume API for asynchronous hosts.
- A checked reference-loading helper and transport-independent cache-action driver in `eyg_hub`; similar draining logic already exists in the CLI's internal client.
- Module/release accessors to avoid external callers depending on entire generated tuple layouts.

### Remote shell and video learnings

The requested recording is implemented at
[`examples/erl_counter/video/erl-counter.mp4`](examples/erl_counter/video/erl-counter.mp4).
It is approximately 69 seconds, silent with captions, H.264/yuv420p MP4, 1600×1008 at 15 fps with fast-start metadata.
There is a [local player](examples/erl_counter/video/index.html), poster, original asciicast, transcript, and chapter timings.

Required sequence:

1. Build and start the application on a named Erlang node.
2. Start a second node with ordinary `erl -sname ... -remsh ...` and verify `node()` is the application's node.
3. Type a real EYG script using `@standard` (the recording uses `list.map` to start three counters and set one-second intervals).
4. Start an application-side session with an empty cache and show the reference is absent.
5. Check the script against the **live** hub without an explicit package-install call or download progress output. The session keeps the returned cache.
6. Show that the reference is now cached but the supervisor still has no counter children.
7. Run the script through the same session. Show its EYG results, three supervised children, and a ticking counter value.

Important observed pitfalls:

- Keeping the large evaluated interpreter cache directly in remote-shell variable bindings stalled the OTP 28 shell after checking, even when the expression returned only `ok`. The precise runtime mechanism was not diagnosed. Do not claim a proven serialization bug.
- Retaining the cache inside `counters_session` and returning only the small result to the shell made the real remote session work. This is the concrete implementation of application-owned cache state, not a reintroduction of global caching.
- `erl -oldshell -remsh` did not produce the intended remote shell in this environment: `node()` identified the shell node. Do not use it as a workaround.
- OTP's line editor redraws the **current** prompt on Enter. A recorder must wait for the **next numbered prompt**, otherwise it can mistake a redraw for command completion.
- Rendering plus real-time recording can exceed a 120-second command timeout. Allow sufficient time; preserve captured output and render it separately when needed.
- `init:stop` is asynchronous. Wait for demo nodes to leave `epmd`; interrupted recordings can leave a detached demo node behind. Clean up only the recorder's named nodes.

Recording uses automated typing into a real PTY; output is not fabricated. `pexpect` captures it, `pyte` reconstructs the terminal, Pillow draws frames, and `imageio-ffmpeg` supplies the encoder.
This environment had no system FFmpeg or Python pip; use `uv` with the checked-in requirements and a local environment under `examples/erl_counter/build`.
Use the existing DejaVu Sans Mono font. Keep all generated media under the project, not `/tmp`.
See [recording instructions](examples/erl_counter/video/README.md) for exact commands, including `--render-only`.
Assertions in the recorder verify that the shell is remote, the dependency changes from absent to cached, check creates no counters, and run creates the expected children.

The current video covers the requested remote-shell/package-loading flow. The original plan's Observer footage, separate single-effect/multiple-effect walkthroughs, and blog post remain unfinished.

### Verification and acceptance criteria

From `examples/erl_counter`:

```sh
gleam build --warnings-as-errors
erl -pa build/dev/erlang/*/ebin -noshell \
  -s erl_counter_test main -s init stop
```

The offline suite currently has **24 passing tests**. Preserve coverage of:

- check has no counter effects; whole-script errors prevent earlier effects;
- direct run from an empty cache and check → run with explicit cache reuse;
- arbitrary and multiple package names; unreferenced ledger entries (including `standard`) are not fetched;
- content dependencies, ledger pagination, historical versions, correct/incorrect pins, and CID mismatches;
- no HTTP for malformed/local code or already loaded references;
- failures return usable caches; separate callers do not inherit hidden state;
- invalid module closures are rejected despite evaluating to a value;
- the application-side session retains the cache and avoids refetching during run;
- counter ticking, stale timer messages, domain error values, shutdown/restart.

Use real hub codecs with injected fetch responses for deterministic tests. Reserve live HTTP for the smoke demonstration/recording.
The actual live recording completed all assertions. Its poster was visually inspected and the entire MP4 successfully decoded with FFmpeg.
The earlier type-diagnostic fix also passed the analysis package's formatting/build checks and 44 Erlang tests.

For future Elixir/Ash work, carry forward the same reference-driven loading, effect whitelist, explicit cache return on all result paths, and application-side session ownership. Do not resurrect the superseded hardcoded preload or hidden-global-cache designs.
