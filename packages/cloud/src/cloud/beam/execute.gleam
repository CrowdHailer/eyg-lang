//// Run EYG code on the cloud platform.
////
//// This module is similar to loam/execute BUT it's not the beam plaform instead it's the cloud platform.
//// Every effect is decided by a policy, see `overlay/policy`.
//// Effects that need the cloud's services, such as posting to a channel, are implemented by a `Host`.

import cloud/system
import eyg/analysis/type_/isomorphic as t
import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import filepath
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/erlang/process
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import ogre/origin
import overlay/check
import overlay/policy
import simplifile
import touch_grass
import touch_grass/cryptography/hash
import touch_grass/decode_json
import touch_grass/env
import touch_grass/fetch
import touch_grass/flip
import touch_grass/harness/computer
import touch_grass/interface
import touch_grass/now
import touch_grass/random
import touch_grass/sleep
import touch_grass/standard_error
import touch_grass/standard_out

pub type Meta =
  #(Int, Int)

pub type Value =
  state.Value(Meta)

pub type Output {
  StandardOut(String)
  StandardError(String)
}

/// same as loam/exectue.State
/// `root` is reserved for trusted configuration. Programs cannot read host files.
pub type State {
  State(origin: origin.Origin, cache: cache.Cache(Meta), root: Option(String))
}

/// The effects a program can perform on the cloud.
pub type Effect {
  Computer(computer.Effect)
  /// Post a message to the conversation the program is running for.
  Post(text: String)
}

/// Implementations of effects that need the cloud's services.
pub type Host {
  Host(post: fn(String) -> Result(String, String))
}

pub type Policy =
  policy.Policy(Effect, Meta)

const computer_effects = [
  "DecodeJSON", "Env", "Fetch", "Flip", "Hash", "Now", "Random", "Sleep",
  "StandardError", "StandardOut",
]

/// Every effect available on the cloud.
pub fn harness() -> interface.Harness(Effect, Meta) {
  computer.effects()
  |> interface.take(computer_effects)
  |> list.map(touch_grass.map(_, Computer))
  |> list.append([post()])
}

fn post() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "Post",
    lift_type: t.String,
    lower_type: t.result(t.String, t.String),
    decode: cast.map(cast.as_string, Post),
  )
}

/// Deterministic computations over supplied values bypass the policy.
/// Every other effect is available only if the policy has a gate for it.
pub const rules = [
  #("DecodeJSON", policy.Unchecked),
  #("Env", policy.PolicyField("env")),
  #("Fetch", policy.PolicyField("fetch")),
  #("Flip", policy.PolicyField("flip")),
  #("Hash", policy.Unchecked),
  #("Now", policy.PolicyField("now")),
  #("Post", policy.PolicyField("post")),
  #("Random", policy.PolicyField("random")),
  #("Sleep", policy.PolicyField("sleep")),
  #("StandardError", policy.PolicyField("standard_error")),
  #("StandardOut", policy.PolicyField("standard_out")),
]

/// Check a complete policy before admitting it. Check gates independently so
/// polymorphic request and reply types are not shared between unrelated effects.
pub fn decode_policy(value: Value, state: State) -> Result(Policy, String) {
  use decoded <- result.try(
    policy.decode_policy(policy.match_rules(harness(), rules), value)
    |> result.map_error(simple_debug.describe),
  )
  use _ <- result.map(
    list.try_map(dict.values(decoded), fn(entry) {
      case entry.condition {
        policy.Unrestricted -> Ok(Nil)
        policy.Gated(gate) ->
          check.value(gate, policy.gate_type(entry.interface), #(0, 0), fn(ref) {
            lookup(ref, state).0
          })
          |> result.map_error(fn(reason) {
            entry.interface.name <> ": " <> reason
          })
      }
    }),
  )
  decoded
}

/// Values supplied by the cloud platform to configuration and programs.
pub fn platform() -> Value {
  v.Record(
    dict.from_list([
      #(
        "reject_all",
        policy.reject_all(policy.match_rules(harness(), rules), #(0, 0)),
      ),
    ]),
  )
}

/// A policy that performs every effect without a gate.
pub fn unrestricted() -> Policy {
  harness()
  |> list.map(fn(interface) {
    #(interface.name, policy.Interface(interface, policy.Unrestricted))
  })
  |> dict.from_list
}

/// The outcome of running a program.
/// Output is held newest first.
pub type Run {
  Run(result: Result(Option(Value), String), output: List(Output))
}

/// Parse and run `code` with the variables in `scope`.
pub fn run(
  code: String,
  scope: List(#(String, Value)),
  policy: Policy,
  host: Host,
  state: State,
) -> #(Run, State) {
  run_with_lookup(code, scope, policy, host, state, program_reference)
}

/// Only trusted workspace configuration can import modules from the host.
pub fn run_configuration(code, policy, host, state) {
  run_with_lookup(code, [], policy, host, state, lookup)
}

fn run_with_lookup(code, scope, policy, host, state, resolve) {
  case parser.all_from_string(code) {
    Error(reason) -> #(Run(Error(parser.format_error(reason, code)), []), state)
    Ok(source) ->
      loop(
        expression.execute(source, [#("cloud", platform()), ..scope]),
        state,
        policy,
        host,
        [],
        resolve,
      )
  }
}

fn loop(
  returned,
  state: State,
  policy,
  host,
  output,
  resolve,
) -> #(Run, State) {
  case returned {
    Ok(value) -> #(Run(Ok(option.Some(value)), output), state)
    Error(#(break.Vacant, _, _, state.Empty)) -> #(
      Run(Ok(option.None), output),
      state,
    )
    Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
      let #(action, state) = decide(policy, label, lift, meta, state)
      case action {
        policy.Perform(interface, input) ->
          case interface.decode(input) {
            Ok(effect) ->
              case perform(effect, host) {
                Ok(#(value, printed)) -> {
                  let output = list.append(printed, output)
                  loop(
                    expression.resume(value, env, k),
                    state,
                    policy,
                    host,
                    output,
                    resolve,
                  )
                }
                Error(reason) -> #(Run(Error(reason), output), state)
              }
            Error(reason) -> #(
              Run(Error(simple_debug.describe(reason)), output),
              state,
            )
          }
        policy.Resume(value) ->
          loop(
            expression.resume(value, env, k),
            state,
            policy,
            host,
            output,
            resolve,
          )
        policy.Failed(#(reason, _, _, _)) -> #(
          Run(Error("Policy failed: " <> simple_debug.describe(reason)), output),
          state,
        )
        policy.Unavailable -> #(
          Run(Error("Effect " <> label <> " is not allowed by policy"), output),
          state,
        )
      }
    }
    Error(#(break.UndefinedReference(reference), _, env, k)) -> {
      let #(value, cache) = resolve(reference, state)
      let state = State(..state, cache:)
      case value {
        Ok(value) ->
          loop(
            expression.resume(value, env, k),
            state,
            policy,
            host,
            output,
            resolve,
          )
        Error(reason) -> #(Run(Error(reason), output), state)
      }
    }
    Error(#(reason, _, _, _)) -> #(
      Run(Error(simple_debug.describe(reason)), output),
      state,
    )
  }
}

/// Ask the policy what to do with an effect.
/// Gates are evaluated purely, they can resolve references but not perform effects.
pub fn decide(
  policy: Policy,
  label: String,
  lift: Value,
  meta: Meta,
  state: State,
) -> #(policy.Action(Meta, Effect), State) {
  policy.decide(
    policy,
    label,
    lift,
    meta,
    fn(returned, then) {
      let #(result, state) = pure_loop(returned, state)
      #(then(result), state)
    },
    fn(action) { #(action, state) },
  )
}

/// Evaluate without effects, resolving references.
pub fn pure_loop(returned, state: State) {
  case returned {
    Ok(value) -> #(Ok(value), state)
    Error(#(break.UndefinedReference(reference), meta, env, k) as debug) -> {
      let #(value, cache) = lookup(reference, state)
      let state = State(..state, cache:)
      case value {
        Ok(value) -> pure_loop(expression.resume(value, env, k), state)
        Error(_) -> #(Error(#(debug.0, meta, env, k)), state)
      }
    }
    Error(debug) -> #(Error(debug), state)
  }
}

fn perform(effect, host: Host) -> Result(#(Value, List(Output)), String) {
  case effect {
    Post(text) -> Ok(#(result_string(host.post(text)), []))
    Computer(effect) ->
      case effect {
        computer.StandardOut(text) ->
          Ok(#(standard_out.encode(Nil), [StandardOut(text)]))
        computer.StandardError(text) ->
          Ok(#(standard_error.encode(Nil), [StandardError(text)]))
        computer.DecodeJson(bytes) -> Ok(#(decode_json.sync(bytes), []))
        computer.Env(name: _) -> Ok(#(env.encode(option.None), []))
        computer.Fetch(request) -> Ok(#(fetch(request), []))
        computer.Flip -> Ok(#(flip.encode(flip.sync()), []))
        computer.Hash(input) -> Ok(#(hash(input), []))
        computer.Now -> Ok(#(now.encode(now.sync()), []))
        computer.Random(max) -> Ok(#(random.encode(random.sync(max)), []))
        computer.Sleep(milliseconds) -> {
          process.sleep(int.max(0, milliseconds))
          Ok(#(sleep.encode(Nil), []))
        }
        _ -> Error("Effect not implemented on the cloud")
      }
  }
}

fn result_string(result) {
  case result {
    Ok(value) -> v.ok(v.String(value))
    Error(reason) -> v.error(v.String(reason))
  }
}

fn program_reference(
  reference: ir.Reference,
  state: State,
) -> #(Result(state.Value(#(Int, Int)), String), cache.Cache(Meta)) {
  case reference {
    ir.Relative(path) -> #(
      Error("Relative import of " <> path <> " is not available"),
      state.cache,
    )
    _ -> lookup_hub(reference, state)
  }
}

/// Resolve references for trusted configuration and its pure checked closures.
pub fn lookup(reference: ir.Reference, state: State) {
  case reference {
    ir.Relative(path) -> relative(path, state)
    _ -> lookup_hub(reference, state)
  }
}

/// Evaluate the module at a path relative to the state's root.
/// Modules are evaluated without effects, their relative imports are read from their own directory.
fn relative(path, state: State) {
  case state.root {
    option.None -> #(
      Error("Relative import of " <> path <> " is not available"),
      state.cache,
    )
    option.Some(root) -> {
      let file = case path {
        "/" <> _ -> path
        _ -> filepath.join(root, path)
      }
      case read_module(file) {
        Error(reason) -> #(Error(reason), state.cache)
        Ok(source) -> {
          let directory = filepath.directory_name(file)
          let state = State(..state, root: option.Some(directory))
          let #(result, state) =
            module_loop(expression.execute(source, []), state, lookup)
          #(result, state.cache)
        }
      }
    }
  }
}

fn read_module(file) {
  use bytes <- result.try(
    simplifile.read_bits(file)
    |> result.map_error(fn(reason) {
      "Failed to read " <> file <> ": " <> simplifile.describe_error(reason)
    }),
  )
  parse_module(bytes, file)
}

fn parse_module(bytes, file) {
  case string.ends_with(file, ".json") {
    True ->
      json.parse_bits(bytes, dag_json.decoder(#(0, 0)))
      |> result.replace_error("Invalid EYG module " <> file)
    False ->
      case bit_array.to_string(bytes) {
        Ok(code) ->
          parser.all_from_string(code)
          |> result.map_error(fn(reason) {
            file <> ": " <> parser.format_error(reason, code)
          })
        Error(Nil) -> Error("Module is not UTF-8 " <> file)
      }
  }
}

fn module_loop(returned, state: State, resolve) {
  case returned {
    Ok(value) -> #(Ok(value), state)
    Error(#(break.Vacant, _, _, state.Empty)) -> #(
      Error("Module has no value"),
      state,
    )
    Error(#(break.UndefinedReference(reference), _, env, k)) -> {
      let #(value, cache) = resolve(reference, state)
      let state = State(..state, cache:)
      case value {
        Ok(value) ->
          module_loop(expression.resume(value, env, k), state, resolve)
        Error(reason) -> #(Error(reason), state)
      }
    }
    Error(#(reason, _, _, _)) -> #(Error(simple_debug.describe(reason)), state)
  }
}

fn lookup_hub(
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

fn fetch(request) {
  httpc.send_bits(request)
  |> result.map_error(string.inspect)
  |> fetch.encode
}

fn hash(input) {
  let hash.Input(algorithm: hash.Sha256, bytes:) = input
  hash.encode(crypto.hash(crypto.Sha256, bytes))
}
