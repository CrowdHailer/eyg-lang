//// This module is similar to loam/execute BUT it's not the beam plaform instead it's the cloud platform.
////
//// The `beam` modules are where continuation based code, which is pure, is turned into idiomatic BEAM code.
//// Functions here perform their effects directly, they block, make requests and call other processes.

import cloud/data/blobs
import cloud/file_system
import cloud/system
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
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
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/tool
import overlay/policy
import simplifile
import touch_grass/cryptography/hash
import touch_grass/decode_json
import touch_grass/env
import touch_grass/fetch
import touch_grass/file_system/append_file
import touch_grass/file_system/delete_file
import touch_grass/file_system/make_directory
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file
import touch_grass/flip
import touch_grass/harness/computer
import touch_grass/now
import touch_grass/random
import touch_grass/sleep
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
    cache: cache.Cache(Meta),
    secrets: Dict(String, String),
    blobs: blobs.Blobs,
    // The module each package reference resolved to, it is used for the rest of the run.
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
  /// Code never asks for a completion, an agent does between running code.
  /// `history` ends with the `added` messages, the rest was sent with earlier completions.
  Complete(
    llm: provider.Llm,
    context: provider.Context,
    history: chat.History,
    added: chat.History,
  )
}

pub type Answer {
  Secret(Option(String))
  Fetched(Result(Response(BitArray), String))
  Number(Int)
  Flipped(Bool)
  Slept
  Completed(Result(chat.Completion(tool.Call), String))
}

/// Code runs until it finishes or waits for the answer to an effect.
pub type Run(a) {
  Finished(
    outcome: Result(a, String),
    state: State,
    root: v1.Cid,
    output: List(String),
  )
  Waiting(
    wait: Wait,
    state: State,
    root: v1.Cid,
    resume: fn(Answer, State, v1.Cid) -> Run(a),
  )
}

/// Answer every effect by performing it.
pub fn complete(
  run: Run(a),
) -> #(Result(a, String), State, v1.Cid, List(String)) {
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
    Complete(llm, context, history, _) ->
      // A completion of a long chat can take minutes.
      provider.completion(llm, context, history, system.slow_fetch(300_000))(
        fn(completion) { completion },
      )
      |> Completed
  }
}

fn answer_to_value(answer) {
  case answer {
    Secret(value) -> env.encode(value)
    Fetched(result) -> fetch.encode(result)
    Number(number) -> v.Integer(number)
    Flipped(value) -> flip.encode(value)
    Slept -> sleep.encode(Nil)
    // Only an agent asks for a completion, code is never resumed with one.
    Completed(_) -> v.unit()
  }
}

fn map(run, f) {
  then(run, fn(outcome, state, root, output) {
    Finished(result.map(outcome, f), state, root, output)
  })
}

/// Continue with `next` when the code finishes, after every effect it waits for.
pub fn then(
  run: Run(a),
  next: fn(Result(a, String), State, v1.Cid, List(String)) -> Run(b),
) -> Run(b) {
  case run {
    Finished(outcome, state, root, output) -> next(outcome, state, root, output)
    Waiting(wait, state, root, resume) ->
      Waiting(wait, state, root, fn(answer, state, root) {
        then(resume(answer, state, root), next)
      })
  }
}

pub type Policy =
  policy.Policy(computer.Effect, Meta)

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

pub fn load_policy(
  code: String,
  state: State,
) -> #(Result(Policy, String), State) {
  case parser.all_from_string(code) {
    Error(reason) -> #(Error(parser.format_error(reason, code)), state)
    Ok(source) -> {
      let #(value, state) = pure_loop(expression.execute(source, []), state)
      let decoded = {
        use value <- result.try(
          result.map_error(value, fn(debug) { simple_debug.describe(debug.0) }),
        )
        policy.decode_policy(
          policy.match_rules(computer.effects(), rules),
          value,
        )
        |> result.map_error(simple_debug.describe)
      }
      #(decoded, state)
    }
  }
}

pub fn block(
  code: String,
  state: State,
  policy: Policy,
  root: v1.Cid,
  emit: fn(Output) -> Nil,
) -> Run(String) {
  evaluate(code, [], simple_debug.inspect, state, policy, root, emit)
}

/// Execute an agent tool with fresh context and capture output for the model.
pub fn run(
  code: String,
  state: State,
  policy: Policy,
  root: v1.Cid,
  emit: fn(Output) -> Nil,
) -> #(Result(String, String), State, v1.Cid, List(String)) {
  tool(code, state, policy, root, emit) |> complete
}

/// Code an agent runs, with `context` in scope, waiting for effects that are not known.
pub fn tool(
  code: String,
  state: State,
  policy: Policy,
  root: v1.Cid,
  emit: fn(Output) -> Nil,
) -> Run(String) {
  evaluate(
    code,
    [#("context", v.unit())],
    agent.inspect_result,
    state,
    policy,
    root,
    emit,
  )
}

fn evaluate(code, scope, inspect, state, policy, root, emit) {
  case parser.all_from_string(code) {
    Error(reason) ->
      Finished(Error(parser.format_error(reason, code)), state, root, [])
    Ok(source) ->
      loop(block.execute(source, scope), state, policy, root, emit, [])
      |> map(fn(value) { value |> option.map(inspect) |> option.unwrap("") })
  }
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
    loop(
      block.call(function, [#(input, #(0, 0))], builtin.default([])),
      state,
      policy,
      root,
      emit,
      [],
    )
    |> complete
  #(result.map(outcome, option.unwrap(_, v.unit())), state, root)
}

fn loop(returned, state: State, policy, root, emit, output) {
  case returned {
    Ok(#(value, _scope)) -> Finished(Ok(value), state, root, output)
    Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
      let continue = fn(outcome, state, root, output) {
        case outcome {
          Ok(value) ->
            block.resume(value, env, k)
            |> loop(state, policy, root, emit, output)
          Error(reason) -> Finished(Error(reason), state, root, output)
        }
      }
      let #(action, state) = decide(policy, label, lift, meta, state)
      case action {
        policy.Perform(interface, input) ->
          case interface.decode(input) {
            Error(reason) ->
              simple_debug.describe(reason)
              |> Error
              |> Finished(state, root, output)
            Ok(effect) ->
              case perform_effect(effect, label, state, root, emit) {
                Error(wait) ->
                  Waiting(wait, state, root, fn(answer, state, root) {
                    continue(Ok(answer_to_value(answer)), state, root, output)
                  })
                Ok(#(outcome, root)) -> {
                  let output = case label, input, outcome {
                    "StandardOut", v.String(text), Ok(_)
                    | "StandardError", v.String(text), Ok(_)
                    -> [text, ..output]
                    _, _, _ -> output
                  }
                  continue(outcome, state, root, output)
                }
              }
          }
        policy.Resume(value) -> continue(Ok(value), state, root, output)
        policy.Failed(debug) ->
          Error("Policy failed: " <> simple_debug.describe(debug.0))
          |> continue(state, root, output)
        policy.Unavailable ->
          continue(Error("Unhandled effect: " <> label), state, root, output)
      }
    }
    Error(#(break.UndefinedReference(reference), _, env, k)) -> {
      let #(value, state) = resolve(reference, [], state, root)
      case value {
        Ok(value) ->
          loop(block.resume(value, env, k), state, policy, root, emit, output)
        Error(reason) -> Finished(Error(reason), state, root, output)
      }
    }
    Error(debug) ->
      Finished(Error(simple_debug.describe(debug.0)), state, root, output)
  }
}

fn resolve(reference, importing, state: State, root) {
  case reference {
    ir.Relative(location) -> import_module(location, importing, state, root)
    _ -> lookup_value(reference, state)
  }
}

/// A module is the value of a file in the file system the code is running against.
/// Code that is run is at the root of the file system, so its imports are relative to there.
/// `importing` is the sequence of modules that lead to this one.
fn import_module(location, importing, state, root) {
  let loaded = {
    use path <- result.try(file_system.resolve_path(location))
    use Nil <- result.try(case list.contains(importing, path) {
      True -> Error("imports itself")
      False -> Ok(Nil)
    })
    use bytes <- result.try(
      files(file_system.read(root, path), state)
      |> result.try(result.map_error(_, simplifile.describe_error)),
    )
    use source <- result.map(parse_module(bytes))
    #(path, absolute(source, path))
  }
  case loaded {
    Ok(#(path, source)) ->
      expression.execute(source, [])
      |> module_loop(state, root, [path, ..importing])
    Error(reason) -> #(Error("import " <> location <> ": " <> reason), state)
  }
}

// Modules are pure, so all a module can need is another module.
fn module_loop(returned, state, root, importing) {
  case returned {
    Ok(value) -> #(Ok(value), state)
    Error(#(break.UndefinedReference(reference), _, env, k)) -> {
      let #(value, state) = resolve(reference, importing, state, root)
      case value {
        Ok(value) ->
          expression.resume(value, env, k)
          |> module_loop(state, root, importing)
        Error(reason) -> #(Error(reason), state)
      }
    }
    Error(debug) -> #(Error(simple_debug.describe(debug.0)), state)
  }
}

/// Modules are the EYG source in a file.
pub fn parse_module(bytes) {
  use code <- result.try(
    bit_array.to_string(bytes) |> result.replace_error("is not text"),
  )
  parser.all_from_string(code)
  |> result.map_error(parser.format_error(_, code))
}

// The imports of a module are relative to its own directory.
// Nothing records where code came from once it is running, a function from a
// module can import when it is called, so locations are made absolute on load.
fn absolute(node, path) {
  let #(expression, meta) = node
  let expression = case expression {
    ir.Reference(ir.Relative("/" <> _)) -> expression
    ir.Reference(ir.Relative(location)) ->
      ir.Reference(ir.Relative(path <> "/../" <> location))
    ir.Lambda(label, body) -> ir.Lambda(label, absolute(body, path))
    ir.Apply(func, argument) ->
      ir.Apply(absolute(func, path), absolute(argument, path))
    ir.Let(label, definition, body) ->
      ir.Let(label, absolute(definition, path), absolute(body, path))
    _ -> expression
  }
  #(expression, meta)
}

fn decide(policy, label, lift, meta, state) {
  case resolve_policy_input(label, lift) {
    Error(reason) -> #(policy.Resume(v.error(v.String(reason))), state)
    Ok(input) ->
      policy.decide(
        policy,
        label,
        input,
        meta,
        fn(returned, then) {
          let #(result, state) = pure_loop(returned, state)
          #(then(result), state)
        },
        fn(action) { #(action, state) },
      )
  }
}

/// TODO remove
fn resolve_policy_input(label, lift) {
  case label, lift {
    "ReadFile", v.Record(fields)
    | "WriteFile", v.Record(fields)
    | "AppendFile", v.Record(fields)
    ->
      case dict.get(fields, "path") {
        Ok(v.String(path)) -> {
          use path <- result.map(file_system.resolve_path(path))
          v.Record(dict.insert(fields, "path", v.String(path)))
        }
        _ -> Ok(lift)
      }
    "DeleteFile", v.String(path)
    | "MakeDirectory", v.String(path)
    | "ReadDirectory", v.String(path)
    -> result.map(file_system.resolve_path(path), v.String)
    _, _ -> Ok(lift)
  }
}

/// Policy evaluation can resolve references but cannot perform effects.
/// TODO this should be continuation based.
pub fn pure_loop(returned, state: State) {
  case returned {
    Error(#(break.UndefinedReference(reference), _, env, k) as debug) -> {
      let #(value, state) = lookup_value(reference, state)
      case value {
        Ok(value) -> pure_loop(expression.resume(value, env, k), state)
        Error(_) -> #(Error(debug), state)
      }
    }
    _ -> #(returned, state)
  }
}

/// Effects that are not known from the code and the file system are returned to wait for.
fn perform_effect(effect, label, state: State, root, emit) {
  case effect {
    computer.StandardOut(text) -> {
      emit(StandardOut(text))
      Ok(#(Ok(standard_out.encode(Nil)), root))
    }
    computer.StandardError(text) -> {
      emit(StandardError(text))
      Ok(#(Ok(standard_error.encode(Nil)), root))
    }
    computer.AppendFile(input) ->
      file_system.append(root, input.path, input.contents)
      |> change(state, root, append_file.encode)
    computer.Cwd -> Ok(#(cwd(), root))
    computer.DecodeJson(bytes) -> Ok(#(decode_json(bytes), root))
    computer.DeleteFile(path) ->
      file_system.delete(root, path) |> change(state, root, delete_file.encode)
    computer.Env(name:) -> Error(Env(name))
    computer.Hash(input) -> Ok(#(hash(input), root))
    computer.MakeDirectory(path) ->
      file_system.make_directory(root, path)
      |> change(state, root, make_directory.encode)
    computer.ReadDirectory(path) ->
      file_system.read_directory(root, path)
      |> read(state, root, read_directory.encode)
    computer.ReadFile(input) ->
      file_system.read_range(root, input.path, input.offset, input.limit)
      |> read(state, root, read_file.encode)
    computer.WriteFile(input) ->
      file_system.write(root, input.path, input.contents)
      |> change(state, root, write_file.encode)
    computer.Fetch(request) -> Error(Fetch(request))
    computer.Flip -> Error(Flip)
    computer.Now -> Error(Now)
    computer.Random(max) -> Error(Random(max))
    computer.Sleep(milliseconds) -> Error(Sleep(milliseconds))
    computer.CreateKey(_)
    | computer.Exit(_)
    | computer.EygParse(_)
    | computer.Sign(_)
    | computer.StandardIn -> Ok(#(Error("Unhandled effect: " <> label), root))
  }
}

// A failed file operation is a value for the program and leaves the root unchanged.
fn change(effect, state, root, encode) {
  case files(effect, state) {
    // A block that cannot be read or written fails the program.
    Error(reason) -> Ok(#(Error(reason), root))
    Ok(Ok(root)) -> Ok(#(Ok(encode(Ok(Nil))), root))
    Ok(Error(reason)) ->
      Ok(#(Ok(encode(Error(simplifile.describe_error(reason)))), root))
  }
}

fn read(effect, state, root, encode) {
  case files(effect, state) {
    Error(reason) -> Ok(#(Error(reason), root))
    Ok(outcome) ->
      Ok(#(
        Ok(encode(result.map_error(outcome, simplifile.describe_error))),
        root,
      ))
  }
}

/// Run file system effects by getting and putting blocks in the blob store.
/// Storage failures stop execution without resuming the effect. The completed
/// value may independently contain a filesystem operation error.
pub fn files(effect: mfs.Effect(a), state: State) -> Result(a, String) {
  case effect {
    mfs.Done(value) -> Ok(value)
    mfs.Get(cid, resume) -> {
      use bytes <- result.try(
        blobs.get(state.blobs, v1.to_string(cid))
        |> result.map_error(fn(reason) {
          "Could not read file system block "
          <> v1.to_string(cid)
          <> ": "
          <> reason
        }),
      )
      use entry <- result.try(
        mfs.decode(cid, bytes)
        |> result.replace_error(
          "Invalid file system block " <> v1.to_string(cid),
        ),
      )
      files(resume(entry), state)
    }
    mfs.Put(entry, resume) -> {
      let stored = mfs.identify(entry)
      use Nil <- result.try(
        blobs.put(state.blobs, v1.to_string(stored.cid), mfs.encode(entry))
        |> result.map_error(fn(reason) {
          "Could not write file system block "
          <> v1.to_string(stored.cid)
          <> ": "
          <> reason
        }),
      )
      files(resume(stored), state)
    }
  }
}

pub type Meta =
  #(Int, Int)

/// A reference to the latest release of a package is resolved once,
/// later references in the same run get the same module even if a new version is released.
pub fn lookup(
  reference: ir.Reference,
  state: State,
) -> #(Result(cache.Module(#(Int, Int)), String), State) {
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

/// The type of a published module.
pub fn lookup_type(reference: ir.Reference, state: State) {
  let #(module, state) = lookup(reference, state)
  #(result.map(module, fn(m) { m.type_ }), state)
}

/// The value of a published module.
pub fn lookup_value(reference: ir.Reference, state: State) {
  let #(module, state) = lookup(reference, state)
  #(result.map(module, fn(m) { m.value }), state)
}

fn flush(cache: cache.Cache(Meta), origin) -> cache.Cache(Meta) {
  let #(cache, actions) = cache.flush(cache)
  case actions {
    [] -> cache
    _ -> {
      let cache =
        list.fold(actions, cache, fn(cache, action) {
          cache.update(cache, compute(action, origin), fn(_) { #(0, 0) }).0
        })
      flush(cache, origin)
    }
  }
}

fn compute(action, origin) {
  cache.compute(action, origin, system.fetch, system.hash)(fn(x) { x })
}

fn cwd() {
  Ok(v.ok(v.String("/")))
}

fn decode_json(bytes) {
  Ok(decode_json.sync(bytes))
}

fn fetch(request) {
  httpc.send_bits(request)
  |> result.map_error(string.inspect)
}

fn hash(input) {
  let hash.Input(algorithm: hash.Sha256, bytes:) = input
  Ok(hash.encode(crypto.hash(crypto.Sha256, bytes)))
}
