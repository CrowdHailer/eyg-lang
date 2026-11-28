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
  )
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
) -> #(Result(String, String), State, v1.Cid, List(String)) {
  let scope = []
  case source.parse(code, source.Inline) {
    Error(reason) -> #(Error(reason), state, root, [])
    Ok(source) -> {
      let #(outcome, state, root, output) =
        outer_loop(
          policy.apply_policy(
            evaluation.await(block.execute(source, scope)),
            policy,
            "/",
          )
            |> evaluation.map(result.map_error(_, describe_debug)),
          state,
          root,
          fn(effect, label, state, root) {
            perform_effect(effect, label, state, root, emit)
          },
          [],
        )
      #(
        result.map(outcome, fn(value) {
          let #(value, _scope) = value
          value |> option.map(agent.inspect_result) |> option.unwrap("")
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
      fn(effect, label, state, root) {
        perform_effect(effect, label, state, root, emit)
      },
      [],
    )
  #(
    result.map(outcome, fn(value) {
      let #(value, _scope) = value
      option.unwrap(value, v.unit())
    }),
    state,
    root,
  )
}

fn outer_loop(returned, state: State, context, perform, output) {
  case returned {
    evaluation.Done(outcome) -> #(outcome, state, context, output)
    evaluation.Conclude(#(reason, _, env, k) as debug, resume) -> {
      let #(outcome, state, context, output) = case reason {
        break.UnhandledEffect(label, input) -> {
          // In Loam there is a separate platform/computer module that implements computer.execute
          // That separation doesn't exist here so we can track output and state etc.
          let effect = computer.cast(label, input)
          let #(outcome, context) = case effect {
            Ok(effect) -> perform(effect, label, state, context)
            Error(break) -> #(Error(describe_reason(break)), context)
          }
          let output = case label, input, outcome {
            "StandardOut", v.String(text), Ok(_)
            | "StandardError", v.String(text), Ok(_)
            -> [text, ..output]
            _, _, _ -> output
          }
          #(outcome, state, context, output)
        }
        break.UndefinedReference(reference) -> {
          let #(value, state) = lookup_value(reference, state)
          #(value, state, context, output)
        }
        _ -> #(Error(describe_debug(debug)), state, context, output)
      }
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
            output,
          )
        Error(reason) -> #(Error(reason), state, context, output)
      }
    }
  }
}

/// Drive an evaluation with reference resolution, rejecting host effects.
pub fn pure(returned, state: State) {
  let #(outcome, state, _, _) =
    outer_loop(
      returned,
      state,
      Nil,
      fn(_effect, label, _, _) {
        #(Error(describe_reason(break.UnhandledEffect(label, v.unit()))), Nil)
      },
      [],
    )
  #(outcome, state)
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
    Error(reason) -> #(Error(reason), root)
    Ok(Ok(root)) -> #(Ok(encode(Ok(Nil))), root)
    Ok(Error(reason)) -> #(
      Ok(encode(Error(simplifile.describe_error(reason)))),
      root,
    )
  }
}

fn read(effect, state, root, encode) {
  case files(effect, state) {
    Error(reason) -> #(Error(reason), root)
    Ok(outcome) -> #(
      Ok(encode(result.map_error(outcome, simplifile.describe_error))),
      root,
    )
  }
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

pub fn lookup(
  reference: ir.Reference,
  state: State,
) -> #(
  Result(cache.Module(source.Location), String),
  cache.Cache(source.Location),
) {
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
      let module = case cache.get_module(cache, cid) {
        Ok(module) -> Ok(module)
        Error(cache.Failed(reason)) -> Error(reason)
        Error(cache.Invalid(reason)) -> Error(simple_debug.describe(reason))
        Error(_) -> Error(missing)
      }
      #(module, cache)
    }
  }
}

/// The type of a published module.
pub fn lookup_type(reference: ir.Reference, state: State) {
  let #(module, cache) = lookup(reference, state)
  let type_ =
    module
    |> result.map(fn(m) { m.type_ })

  #(type_, State(..state, cache:))
}

pub fn lookup_value(reference: ir.Reference, state: State) {
  let #(module, cache) = lookup(reference, state)
  let value =
    module
    |> result.map(fn(m) { m.value })

  #(value, State(..state, cache:))
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

pub fn describe_debug(debug: state.Debug(m)) -> String {
  describe_reason(debug.0)
}

pub fn describe_reason(reason: state.Reason(_)) -> String {
  simple_debug.describe(reason)
}
