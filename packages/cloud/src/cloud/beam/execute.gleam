//// This module is similar to loam/execute BUT it's not the beam plaform instead it's the cloud platform.
////
//// The `beam` modules are where continuation based code, which is pure, is turned into idiomatic BEAM code.
//// Functions here perform their effects directly, they block, make requests and call other processes.

import bucket/get_object
import bucket/put_object
import cloud/blobs/blobs
import cloud/config
import cloud/file_system
import cloud/system
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug as type_debug
import eyg/analysis/type_/binding/error
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/evaluation
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import multiformats/cid/v1
import ogre/origin
import overlay/agent
import simplifile
import touch_grass/cryptography/hash
import touch_grass/decode_json
import touch_grass/env
import touch_grass/fetch
import touch_grass/file_system as file_system_request
import touch_grass/file_system/append_file
import touch_grass/file_system/delete_file
import touch_grass/file_system/make_directory
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file
import touch_grass/flip
import touch_grass/harness/computer
import touch_grass/interface
import touch_grass/now
import touch_grass/policy
import touch_grass/random
import touch_grass/sleep
import touch_grass/source
import touch_grass/standard_error
import touch_grass/standard_out
import unixfs/mfs

pub type Output {
  StandardOut(String)
  StandardError(String)
}

pub type State {
  State(
    origin: origin.Origin,
    cache: cache.Cache(source.Location),
    secrets: Dict(String, String),
    bucket: config.S3Bucket,
    // The module each package reference resolved to when the code was checked, the code runs with it.
    pins: Dict(ir.Reference, v1.Cid),
  )
}

/// Effects whose result is not known from the code and the file system.
pub type Wait {
  Env(String)
  Fetch(Request(BitArray))
  Random(Int)
  Now
  Flip
  Sleep(Int)
}

pub type Answer {
  Secret(Option(String))
  Fetched(Result(Response(BitArray), String))
  Number(Int)
  Flipped(Bool)
  Slept
  /// The box rejected the files changed before the wait, so they were discarded.
  /// Code that waited fails with the reason.
  Rejected(String)
}

/// Code runs until it finishes or waits for the answer to an effect.
/// `context` is what the code runs against, such as the root of a file system.
pub type Running(a, context) {
  Finished(
    outcome: Result(a, String),
    state: State,
    root: context,
    output: List(String),
  )
  Waiting(
    wait: Wait,
    state: State,
    root: context,
    resume: fn(Answer, State, context) -> Running(a, context),
  )
}

/// Code that runs against a file system.
pub type Run(a) =
  Running(a, v1.Cid)

/// Answer every effect by performing it.
pub fn complete(
  run: Running(a, context),
) -> #(Result(a, String), State, context, List(String)) {
  case run {
    Finished(outcome, state, root, output) -> #(outcome, state, root, output)
    Waiting(wait, state, root, resume) ->
      complete(resume(perform(wait, state), state, root))
  }
}

pub fn perform(wait: Wait, state: State) -> Answer {
  case wait {
    Env(name) -> Secret(dict.get(state.secrets, name) |> option.from_result)
    Fetch(request) -> Fetched(fetch(request))
    Random(max) -> Number(random.sync(max))
    Now -> Number(now.sync())
    Flip -> Flipped(flip.sync())
    Sleep(milliseconds) -> {
      process.sleep(int.max(0, milliseconds))
      Slept
    }
  }
}

fn answer_to_value(answer) {
  case answer {
    Secret(value) -> env.encode(value)
    Fetched(result) -> fetch.encode(result)
    Number(number) -> v.Integer(number)
    Flipped(value) -> flip.encode(value)
    Slept -> sleep.encode(Nil)
    // Code that waited fails when its changes are rejected, see `outer_loop`.
    Rejected(_) -> v.unit()
  }
}

/// Continue with `next` when the code finishes, after every effect it waits for.
pub fn then(
  run: Running(a, context),
  next: fn(Result(a, String), State, context, List(String)) ->
    Running(b, context),
) -> Running(b, context) {
  case run {
    Finished(outcome, state, root, output) -> next(outcome, state, root, output)
    Waiting(wait, state, root, resume) ->
      Waiting(wait, state, root, fn(answer, state, root) {
        then(resume(answer, state, root), next)
      })
  }
}

pub type Policy =
  policy.Policy(computer.Effect, source.Location)

pub const rules = [
  #("AppendFile", policy.PolicyField("append_file")),
  #("CWD", policy.PolicyField("cwd")),
  #("DecodeJSON", policy.Unchecked),
  #("DeleteFile", policy.PolicyField("delete_file")),
  #("Env", policy.PolicyField("env")),
  #("Fetch", policy.PolicyField("fetch")),
  #("Flip", policy.PolicyField("flip")),
  #("Hash", policy.Unchecked),
  #("MakeDirectory", policy.PolicyField("make_directory")),
  #("Now", policy.PolicyField("now")),
  #("Random", policy.PolicyField("random")),
  #("ReadDirectory", policy.PolicyField("read_directory")),
  #("ReadFile", policy.PolicyField("read_file")),
  #("Sleep", policy.PolicyField("sleep")),
  #("StandardError", policy.PolicyField("standard_error")),
  #("StandardOut", policy.PolicyField("standard_out")),
  #("WriteFile", policy.PolicyField("write_file")),
]

pub fn template() -> List(
  #(interface.Interface(computer.Effect, a), policy.Rule),
) {
  policy.match_rules(computer.effects(), rules)
}

pub fn load_policy(
  code: String,
  origin: source.Origin,
  state: State,
  template: List(
    #(interface.Interface(computer.Effect, source.Location), policy.Rule),
  ),
) -> #(Result(Policy, String), State) {
  case source.parse(code, origin) {
    Error(reason) -> #(Error(reason), state)
    Ok(source) -> {
      let #(analysis, state) = check_loop(policy.check(source, template), state)
      case infer.all_errors(analysis) {
        [] -> pure(policy.prepare_source(source, template), state)
        errors -> #(Error(type_errors(errors)), state)
      }
    }
  }
}

fn type_errors(errors: List(#(source.Location, error.Reason))) {
  errors
  |> list.map(fn(error) { type_debug.render_reason(error.1) })
  |> string.join("\n")
}

fn check_loop(step, state: State) {
  case step {
    infer.Done(analysis) -> #(analysis, state)
    infer.Lookup(reference, resume) -> {
      let #(type_, state) = lookup_type(reference, state)
      check_loop(resume(result.replace_error(type_, Nil)), state)
    }
  }
}

pub fn run(
  code: String,
  state: State,
  policy: Policy,
  root: v1.Cid,
  emit: fn(Output) -> Nil,
) -> Run(String) {
  case source.parse(code, source.Inline) {
    Error(reason) -> Finished(Error(reason), state, root, [])
    Ok(source) -> run_source(source, state, policy, root, emit)
  }
}

/// Run a program that was built rather than written, such as in a structural editor.
pub fn program(
  source: ir.Node(Nil),
  state: State,
  policy: Policy,
  root: v1.Cid,
  emit: fn(Output) -> Nil,
) -> Run(String) {
  let meta = source.Location(source.Inline, source.Json)
  ir.map_annotation(source, fn(_) { meta })
  |> run_source(state, policy, root, emit)
}

/// Code is run as a block, it can end without a value.
fn run_source(source, state, policy, root, emit) {
  use state, modules <- checked(source, policy, state, root)
  use outcome, state, root, output <- then(
    outer_loop(
      policy.apply_policy(
        evaluation.await(block.execute(source, [])),
        policy,
        "/",
      )
        |> evaluation.map(result.map_error(_, describe_debug)),
      state,
      root,
      fn(effect, _label, state, root) {
        perform_effect(effect, state, root, emit)
      },
      fn(location, meta, _state, _root) { imported(modules, location, meta) },
      [],
    ),
  )
  Finished(
    result.map(outcome, fn(value) {
      let #(value, _scope) = value
      value |> option.map(agent.inspect_result) |> option.unwrap("")
    }),
    state,
    root,
    output,
  )
}

/// Type check code before it runs, with the effects the policy offers.
/// Each package it refers to is pinned to the module it resolves to, so it runs with the modules it was checked with.
/// Every module it imports is loaded from the file system and checked, the code runs with the loaded modules.
fn checked(source, policy: Policy, state, root, then) {
  let effects =
    dict.values(policy)
    |> list.map(fn(entry) { entry.interface })
    |> interface.types
  let context = infer.pure() |> infer.with_effects(effects)
  let checking = infer.check(context, source)
  case check_imports(checking, option.Some("/"), [], state, root, dict.new()) {
    Error(reason) -> Finished(Error(reason), state, root, [])
    Ok(#(analysis, state, modules)) ->
      case infer.all_errors(analysis) {
        [] -> then(state, dict.map_values(modules, fn(_, module) { module.1 }))
        errors -> Finished(Error(type_errors(errors)), state, root, [])
      }
  }
}

/// Check code, loading each module it imports relative to `directory`.
/// `importing` is the sequence of modules being imported, to refuse a module that imports itself.
fn check_imports(checking, directory, importing, state, root, modules) {
  case checking {
    infer.Done(analysis) -> Ok(#(analysis, state, modules))
    infer.Lookup(ir.Relative(location), resume) -> {
      use #(type_, state, modules) <- result.try(
        import_module(location, directory, importing, state, root, modules)
        |> result.map_error(fn(reason) {
          "import " <> location <> ": " <> reason
        }),
      )
      check_imports(
        resume(Ok(type_)),
        directory,
        importing,
        state,
        root,
        modules,
      )
    }
    infer.Lookup(reference, resume) -> {
      let #(type_, state) = lookup_type(reference, state)
      resume(result.replace_error(type_, Nil))
      |> check_imports(directory, importing, state, root, modules)
    }
  }
}

/// A module is the source of a file in the file system the code is running against.
/// Its imports are relative to its own directory, and it is pure.
fn import_module(location, directory, importing, state, root, modules) {
  use path <- result.try(
    file_system_request.resolve_path(directory, location)
    |> result.replace_error("invalid path"),
  )
  use Nil <- result.try(case list.contains(importing, path) {
    True -> Error("imports itself")
    False -> Ok(Nil)
  })
  case dict.get(modules, path) {
    Ok(#(type_, _source)) -> Ok(#(type_, state, modules))
    Error(Nil) -> {
      use bytes <- result.try(
        files(file_system.read(root, path), state)
        |> result.try(result.map_error(_, simplifile.describe_error)),
      )
      use code <- result.try(
        bit_array.to_string(bytes) |> result.replace_error("is not text"),
      )
      use source <- result.try(source.parse(code, source.Host(path)))
      let checking = infer.check(infer.pure(), source)
      let directory = source.base(source.Host(path), "/")
      use #(analysis, state, modules) <- result.try(check_imports(
        checking,
        directory,
        [path, ..importing],
        state,
        root,
        modules,
      ))
      case infer.all_errors(analysis) {
        [] -> {
          let type_ = infer.poly_type(analysis)
          Ok(#(type_, state, dict.insert(modules, path, #(type_, source))))
        }
        errors -> Error(type_errors(errors))
      }
    }
  }
}

/// The source of a module the code imports, it was loaded when the code was checked.
fn imported(modules, location, meta: source.Location) {
  use path <- result.try(
    file_system_request.resolve_path(source.base(meta.origin, "/"), location)
    |> result.replace_error("import " <> location <> ": invalid path"),
  )
  dict.get(modules, path)
  |> result.replace_error("import " <> location <> ": not loaded")
}

/// Run a checked automation through the same policy-gated loop as other code.
pub fn call(function, input, state: State, policy: Policy, root, emit) {
  let #(outcome, state, root) =
    call_value(function, input, state, policy, root, emit)
  #(result.replace(outcome, Nil), state, root)
}

/// Preserve the result of a trigger while applying the normal effect policy.
pub fn call_value(function, input, state: State, policy: Policy, root, emit) {
  let #(outcome, state, root, _) =
    outer_loop(
      policy.apply_policy(
        evaluation.await(block.call(
          function,
          [#(input, source.Location(source.Inline, source.Json))],
          builtin.default([]),
        )),
        policy,
        "/",
      )
        |> evaluation.map(result.map_error(_, describe_debug)),
      state,
      root,
      fn(effect, _label, state, root) {
        perform_effect(effect, state, root, emit)
      },
      fn(location, _meta, _state, _root) {
        Error("import " <> location <> ": not loaded")
      },
      [],
    )
    |> complete
  #(
    result.map(outcome, fn(value) {
      let #(value, _scope) = value
      option.unwrap(value, v.unit())
    }),
    state,
    root,
  )
}

/// What performing an effect did.
type Performed(context) {
  /// The value for the code, and what it runs against after the effect.
  Answers(state.Value(source.Location), context)
  /// The result is not known from the code and the file system, the caller answers it.
  Waits(Wait)
}

fn outer_loop(
  returned,
  state: State,
  context,
  perform,
  load,
  output,
) -> Running(a, context) {
  case returned {
    evaluation.Done(outcome) -> Finished(outcome, state, context, output)
    // A module is evaluated in place of its import, with an empty policy so it is pure.
    evaluation.Conclude(
      #(break.UndefinedReference(ir.Relative(location)), meta, env, k) as debug,
      resume,
    ) ->
      case load(location, meta, state, context) {
        Error(reason) -> Finished(Error(reason), state, context, output)
        Ok(source) -> {
          let next = {
            let module =
              evaluation.await(block.execute(source, []))
              |> policy.apply_policy(dict.new(), "/")
            use returned <- evaluation.then(module)
            case returned {
              Ok(#(option.Some(value), _scope)) ->
                evaluation.then(
                  evaluation.await(expression.resume(value, env, k)),
                  resume,
                )
              Ok(#(option.None, _scope)) -> resume(Error(debug))
              Error(debug) -> resume(Error(debug))
            }
          }
          outer_loop(next, state, context, perform, load, output)
        }
      }
    evaluation.Conclude(#(reason, _, env, k) as debug, resume) -> {
      let continue = fn(outcome, state, context, output) {
        case outcome {
          Ok(value) ->
            outer_loop(
              evaluation.then(
                evaluation.await(expression.resume(value, env, k)),
                resume,
              ),
              state,
              context,
              perform,
              load,
              output,
            )
          Error(reason) -> Finished(Error(reason), state, context, output)
        }
      }
      case reason {
        break.UnhandledEffect(label, input) -> {
          // In Loam there is a separate platform/computer module that implements computer.execute
          // That separation doesn't exist here so we can track output and state etc.
          let effect =
            computer.cast(label, input) |> result.map_error(describe_reason)
          case result.try(effect, perform(_, label, state, context)) {
            // A block of the file system that cannot be read or written fails the run.
            Error(reason) -> Finished(Error(reason), state, context, output)
            Ok(Waits(wait)) ->
              Waiting(wait, state, context, fn(answer, state, context) {
                case answer {
                  Rejected(reason) ->
                    Finished(Error(reason), state, context, output)
                  _ ->
                    continue(
                      Ok(answer_to_value(answer)),
                      state,
                      context,
                      output,
                    )
                }
              })
            Ok(Answers(value, context)) -> {
              let output = case effect {
                Ok(computer.StandardOut(text))
                | Ok(computer.StandardError(text)) -> [text, ..output]
                _ -> output
              }
              continue(Ok(value), state, context, output)
            }
          }
        }
        break.UndefinedReference(reference) -> {
          let #(value, state) = lookup_value(reference, state)
          continue(value, state, context, output)
        }
        _ -> continue(Error(describe_debug(debug)), state, context, output)
      }
    }
  }
}

/// Drive an evaluation with reference resolution, rejecting host effects.
pub fn pure(returned, state: State) {
  case
    outer_loop(
      returned,
      state,
      Nil,
      fn(_effect, label, _, _) {
        Error(describe_reason(break.UnhandledEffect(label, v.unit())))
      },
      fn(location, _, _, _) { Error("import " <> location <> ": not loaded") },
      [],
    )
  {
    Finished(outcome, state, _, _) -> #(outcome, state)
    // A pure evaluation performs no effects so never waits.
    Waiting(state:, ..) -> #(Error("a pure evaluation waited"), state)
  }
}

/// A block of the file system that cannot be read or written is an error.
fn perform_effect(effect, state: State, root, emit) {
  case effect {
    computer.StandardOut(text) -> {
      emit(StandardOut(text))
      Ok(Answers(standard_out.encode(Nil), root))
    }
    computer.StandardError(text) -> {
      emit(StandardError(text))
      Ok(Answers(standard_error.encode(Nil), root))
    }
    computer.AppendFile(input) ->
      file_system.append(root, input.path, input.contents)
      |> change(state, root, append_file.encode)
    computer.Cwd -> Ok(Answers(v.ok(v.String("/")), root))
    computer.DecodeJson(bytes) -> Ok(Answers(decode_json.sync(bytes), root))
    computer.DeleteFile(path) ->
      file_system.delete(root, path) |> change(state, root, delete_file.encode)
    computer.Env(name:) -> Ok(Waits(Env(name)))
    computer.Fetch(request) -> Ok(Waits(Fetch(request)))
    computer.Flip -> Ok(Waits(Flip))
    computer.Hash(input) -> Ok(Answers(hash(input), root))
    computer.MakeDirectory(path) ->
      file_system.make_directory(root, path)
      |> change(state, root, make_directory.encode)
    computer.Now -> Ok(Waits(Now))
    computer.Random(max) -> Ok(Waits(Random(max)))
    computer.ReadDirectory(path) ->
      file_system.read_directory(root, path)
      |> read(state, root, read_directory.encode)
    computer.ReadFile(input) ->
      file_system.read_range(root, input.path, input.offset, input.limit)
      |> read(state, root, read_file.encode)
    computer.Sleep(milliseconds) -> Ok(Waits(Sleep(milliseconds)))
    computer.WriteFile(input) ->
      file_system.write(root, input.path, input.contents)
      |> change(state, root, write_file.encode)
    // The rules offer no other effect of the harness.
    computer.CreateKey(_)
    | computer.Exit(_)
    | computer.EygParse(_)
    | computer.Sign(_)
    | computer.StandardIn -> Error("Unhandled effect")
  }
}

// A failed file operation is a value for the program and leaves the root unchanged.
fn change(effect, state, root, encode) {
  use changed <- result.map(files(effect, state))
  case changed {
    Ok(root) -> Answers(encode(Ok(Nil)), root)
    Error(reason) ->
      Answers(encode(Error(simplifile.describe_error(reason))), root)
  }
}

fn read(effect, state, root, encode) {
  use outcome <- result.map(files(effect, state))
  Answers(encode(result.map_error(outcome, simplifile.describe_error)), root)
}

/// Run file system effects by getting and putting blocks in the blob store.
/// Storage failures stop execution without resuming the effect. The completed
/// value may independently contain a filesystem operation error.
pub fn files(effect: mfs.Effect(a), state: State) -> Result(a, String) {
  case effect {
    mfs.Done(value) -> Ok(value)
    mfs.Get(cid, resume) -> {
      use found <- result.try(
        blobs.get(state.bucket, cid)
        |> result.map_error(blobs.describe_reason),
      )
      case found {
        get_object.Found(bytes) -> {
          use entry <- result.try(
            mfs.decode(cid, bytes)
            |> result.replace_error(
              "Invalid file system block " <> v1.to_string(cid),
            ),
          )
          files(resume(entry), state)
        }
        get_object.NotFound -> Error("not found")
      }
    }
    mfs.Put(entry, resume) -> {
      let stored = mfs.identify(entry)
      use put_object.PutObjectResult(_etag) <- result.try(
        blobs.put(state.bucket, stored.cid, mfs.encode(entry))
        |> result.map_error(blobs.describe_reason),
      )
      files(resume(stored), state)
    }
  }
}

/// A reference to a package is pinned to the module it resolves to.
pub fn lookup(
  reference: ir.Reference,
  state: State,
) -> #(Result(cache.Module(source.Location), String), State) {
  case dict.get(state.pins, reference) {
    Ok(cid) -> lookup(ir.Content(cid), state)
    Error(Nil) -> {
      let #(module, cache, cid) = resolve_reference(reference, state)
      let pins = case reference, cid {
        ir.Package(..), Ok(cid) | ir.Version(..), Ok(cid) ->
          dict.insert(state.pins, reference, cid)
        _, _ -> state.pins
      }
      #(module, State(..state, cache:, pins:))
    }
  }
}

fn resolve_reference(reference, state: State) {
  let refresh = case reference {
    ir.Content(_) | ir.Relative(_) -> False
    _ -> True
  }
  let cache = case refresh {
    False -> state.cache
    True -> flush(cache.pull(state.cache), state.origin)
  }
  let missing = simple_debug.describe(break.UndefinedReference(reference))
  let cid = case reference {
    ir.Content(cid) -> Ok(cid)
    ir.Package(name) ->
      cache.package(cache, name) |> result.map(fn(entry) { entry.module })
    ir.Version(name, version) -> cache.unbound_release(cache, name, version)
    ir.Pinned(release) ->
      case cache.release(cache, release) {
        cache.Available(cid) -> Ok(cid)
        _ -> Error(Nil)
      }
    ir.Relative(_) -> Error(Nil)
  }
  case cid, cache.cursor_status {
    _, cache.PullFailed(reason) if refresh -> #(Error(reason), cache, Error(Nil))
    Error(Nil), _ -> #(Error(missing), cache, Error(Nil))
    Ok(cid), _ -> {
      let cache = flush(cache.fetch(cache, cid), state.origin)
      let module = case cache.get_module(cache, cid) {
        Ok(module) -> Ok(module)
        Error(cache.Failed(reason)) -> Error(reason)
        Error(cache.Invalid(reason)) -> Error(simple_debug.describe(reason))
        Error(_) -> Error(missing)
      }
      #(module, cache, result.replace_error(module, Nil) |> result.replace(cid))
    }
  }
}

/// The type of a published module, checking code pins the packages it refers to.
pub fn lookup_type(reference: ir.Reference, state: State) {
  let #(module, state) = lookup(reference, state)
  #(result.map(module, fn(m) { m.type_ }), state)
}

/// The value of a published module, a package must have been pinned when the code was checked.
pub fn lookup_value(reference: ir.Reference, state: State) {
  case reference, dict.get(state.pins, reference) {
    ir.Package(..), Error(Nil) | ir.Version(..), Error(Nil) -> #(
      Error(
        simple_debug.describe(break.UndefinedReference(reference))
        <> ", not pinned",
      ),
      state,
    )
    _, _ -> {
      let #(module, state) = lookup(reference, state)
      #(result.map(module, fn(m) { m.value }), state)
    }
  }
}

fn flush(
  cache: cache.Cache(source.Location),
  origin,
) -> cache.Cache(source.Location) {
  let #(cache, actions) = cache.flush(cache)
  case actions {
    [] -> cache
    _ -> {
      let cache =
        list.fold(actions, cache, fn(cache, action) {
          cache.update(cache, compute(action, origin), fn(_) {
            // TODO this should be correct based on the action
            source.Location(source.Inline, source.Json)
          }).0
        })
      flush(cache, origin)
    }
  }
}

fn compute(action, origin) {
  cache.compute(action, origin, system.fetch, system.hash)(fn(x) { x })
}

fn fetch(request) {
  httpc.send_bits(request)
  |> result.map_error(string.inspect)
}

fn hash(input) {
  let hash.Input(algorithm: hash.Sha256, bytes:) = input
  hash.encode(crypto.hash(crypto.Sha256, bytes))
}

pub fn describe_debug(debug: state.Debug(m)) -> String {
  describe_reason(debug.0)
}

pub fn describe_reason(reason: state.Reason(_)) -> String {
  simple_debug.describe(reason)
}
