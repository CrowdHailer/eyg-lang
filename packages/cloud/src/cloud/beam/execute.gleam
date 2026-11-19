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
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import multiformats/cid/v1
import ogre/origin
import overlay/agent
import overlay/policy
import simplifile.{type FileError}
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
  )
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
) -> #(Result(String, String), State, v1.Cid, List(String)) {
  evaluate(code, [], simple_debug.inspect, state, policy, root, emit)
}

/// Execute an agent tool with fresh context and capture output for the model.
/// TODO I think the agent can use block execute as well.
pub fn run(
  code: String,
  state: State,
  policy: Policy,
  root: v1.Cid,
  emit: fn(Output) -> Nil,
) -> #(Result(String, String), State, v1.Cid, List(String)) {
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
    Error(reason) -> #(
      Error(parser.format_error(reason, code)),
      state,
      root,
      [],
    )
    Ok(source) -> {
      let #(outcome, state, root, output) =
        loop(block.execute(source, scope), state, policy, root, emit, [])
      #(
        result.map(outcome, fn(value) {
          value |> option.map(inspect) |> option.unwrap("")
        }),
        state,
        root,
        output,
      )
    }
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
  #(result.map(outcome, option.unwrap(_, v.unit())), state, root)
}

fn loop(returned, state: State, policy, root, emit, output) {
  case returned {
    Ok(#(value, _scope)) -> #(Ok(value), state, root, output)
    Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
      let #(action, state) = decide(policy, label, lift, meta, state)
      let #(outcome, root, output) = case action {
        policy.Perform(interface, input) -> {
          let #(outcome, root) = case interface.decode(input) {
            Ok(effect) -> perform_effect(effect, label, state, root, emit)
            Error(reason) -> #(Error(simple_debug.describe(reason)), root)
          }
          let output = case label, input, outcome {
            "StandardOut", v.String(text), Ok(_)
            | "StandardError", v.String(text), Ok(_)
            -> [text, ..output]
            _, _, _ -> output
          }
          #(outcome, root, output)
        }
        policy.Resume(value) -> #(Ok(value), root, output)
        policy.Failed(debug) -> #(
          Error("Policy failed: " <> simple_debug.describe(debug.0)),
          root,
          output,
        )
        policy.Unavailable -> #(
          Error("Unhandled effect: " <> label),
          root,
          output,
        )
      }
      case outcome {
        Ok(value) ->
          loop(block.resume(value, env, k), state, policy, root, emit, output)
        Error(reason) -> #(Error(reason), state, root, output)
      }
    }
    Error(#(break.UndefinedReference(reference), _, env, k)) -> {
      let #(value, cache) = lookup(reference, state)
      let state = State(..state, cache:)
      case value {
        Ok(value) ->
          loop(block.resume(value, env, k), state, policy, root, emit, output)
        Error(reason) -> #(Error(reason), state, root, output)
      }
    }
    Error(debug) -> #(
      Error(simple_debug.describe(debug.0)),
      state,
      root,
      output,
    )
  }
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
      let #(value, cache) = lookup(reference, state)
      let state = State(..state, cache:)
      case value {
        Ok(value) -> pure_loop(expression.resume(value, env, k), state)
        Error(_) -> #(Error(debug), state)
      }
    }
    _ -> #(returned, state)
  }
}

fn perform_effect(effect, label, state: State, root, emit) {
  case effect {
    computer.StandardOut(text) -> {
      emit(StandardOut(text))
      #(Ok(standard_out.encode(Nil)), root)
    }
    computer.StandardError(text) -> {
      emit(StandardError(text))
      #(Ok(standard_error.encode(Nil)), root)
    }
    computer.AppendFile(input) ->
      file_system.append(root, input.path, input.contents)
      |> change(state, root, append_file.encode)
    computer.Cwd -> #(cwd(), root)
    computer.DecodeJson(bytes) -> #(decode_json(bytes), root)
    computer.DeleteFile(path) ->
      file_system.delete(root, path) |> change(state, root, delete_file.encode)
    computer.Env(name:) -> #(get_env(name, state.secrets), root)
    computer.Fetch(request) -> #(fetch(request), root)
    computer.Flip -> #(flip(), root)
    computer.Hash(input) -> #(hash(input), root)
    computer.MakeDirectory(path) ->
      file_system.make_directory(root, path)
      |> change(state, root, make_directory.encode)
    computer.Now -> #(now(), root)
    computer.Random(max) -> #(random(max), root)
    computer.ReadDirectory(path) ->
      file_system.read_directory(root, path)
      |> read(state, root, read_directory.encode)
    computer.ReadFile(input) ->
      file_system.read_range(root, input.path, input.offset, input.limit)
      |> read(state, root, read_file.encode)
    computer.Sleep(milliseconds) -> #(sleep(milliseconds), root)
    computer.WriteFile(input) ->
      file_system.write(root, input.path, input.contents)
      |> change(state, root, write_file.encode)
    computer.CreateKey(_)
    | computer.Exit(_)
    | computer.EygParse(_)
    | computer.Sign(_)
    | computer.StandardIn -> #(Error("Unhandled effect: " <> label), root)
  }
}

// A failed file operation is a value for the program and leaves the root unchanged.
fn change(effect, state, root, encode) {
  case files(effect, state) {
    Ok(root) -> #(Ok(encode(Ok(Nil))), root)
    Error(reason) -> #(
      Ok(encode(Error(simplifile.describe_error(reason)))),
      root,
    )
  }
}

fn read(effect, state, root, encode) {
  let outcome =
    files(effect, state) |> result.map_error(simplifile.describe_error)
  #(Ok(encode(outcome)), root)
}

/// Run file system effects by getting and putting blocks in the blob store.
pub fn files(effect: mfs.Effect(a), state: State) -> Result(a, FileError) {
  case effect {
    mfs.Done(value) -> value
    mfs.Get(cid, resume) ->
      blobs.get(state.blobs, v1.to_string(cid))
      |> result.replace_error(Nil)
      |> result.try(mfs.decode(cid, _))
      |> result.replace_error(simplifile.Enoent)
      |> resume
      |> files(state)
    mfs.Put(entry, resume) -> {
      let stored = mfs.identify(entry)
      blobs.put(state.blobs, v1.to_string(stored.cid), mfs.encode(entry))
      |> result.replace(stored)
      |> result.replace_error(simplifile.Eio)
      |> resume
      |> files(state)
    }
  }
}

pub type Meta =
  #(Int, Int)

pub fn lookup(
  reference: ir.Reference,
  state: State,
) -> #(Result(state.Value(#(Int, Int)), String), cache.Cache(Meta)) {
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
    _, cache.PullFailed(reason) if refresh -> #(Error(reason), cache)
    Error(Nil), _ -> #(Error(missing), cache)
    Ok(cid), _ -> {
      let cache = flush(cache.fetch(cache, cid), state.origin)
      let value = case cache.get_module(cache, cid) {
        Ok(module) -> Ok(module.value)
        Error(cache.Failed(reason)) -> Error(reason)
        Error(cache.Invalid(reason)) -> Error(simple_debug.describe(reason))
        Error(_) -> Error(missing)
      }
      #(value, cache)
    }
  }
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

fn get_env(name, secrets) {
  Ok(dict.get(secrets, name) |> option.from_result |> env.encode)
}

fn fetch(request) {
  httpc.send_bits(request)
  |> result.map_error(string.inspect)
  |> fetch.encode
  |> Ok
}

fn flip() {
  Ok(flip.encode(flip.sync()))
}

fn hash(input) {
  let hash.Input(algorithm: hash.Sha256, bytes:) = input
  Ok(hash.encode(crypto.hash(crypto.Sha256, bytes)))
}

fn now() {
  Ok(now.encode(now.sync()))
}

fn random(max) {
  Ok(random.encode(random.sync(max)))
}

fn sleep(milliseconds) {
  process.sleep(int.max(0, milliseconds))
  Ok(sleep.encode(Nil))
}
