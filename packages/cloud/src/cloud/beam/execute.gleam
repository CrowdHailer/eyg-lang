//// Run EYG code on the cloud platform.
////
//// This module is similar to loam/execute BUT it's not the beam plaform instead it's the cloud platform.
//// Every effect is decided by a policy, see `overlay/policy`.
//// Effects that need the cloud's services, such as posting to a channel, are implemented by a `Host`.

import cloud/files
import cloud/system
import cloud/trigger
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
import gleam/erlang/process.{type Subject}
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import midas/continuation
import ogre/origin
import overlay/check
import overlay/policy
import simplifile
import touch_grass
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
  /// Read a secret from the workspace's secrets store, only available to the workspace configuration.
  Secret(name: String)
  /// Install a trigger in the program's channel.
  AddTrigger(trigger.Trigger)
  StopTrigger(name: String)
  StartTrigger(name: String)
  DeleteTrigger(name: String)
  ListTriggers
  /// Run a subagent with the channel shell to complete a task, returns its final reply.
  Delegate(task: String)
}

/// Implementations of effects that need the cloud's services.
pub type Host {
  Host(
    post: fn(String) -> Result(String, String),
    secret: fn(String) -> Result(String, String),
    files: Files,
    triggers: Triggers,
    subagent: fn(String) -> Result(String, String),
  )
}

/// The triggers of the program's channel.
pub type Triggers {
  Triggers(
    add: fn(trigger.Trigger) -> Result(Nil, String),
    /// Stop, start or delete the named trigger.
    update: fn(String, TriggerUpdate) -> Result(Nil, String),
    list: fn() -> List(trigger.Trigger),
  )
}

pub type TriggerUpdate {
  Stop
  Start
  Delete
}

pub fn no_triggers() -> Triggers {
  Triggers(
    add: fn(_) { Error("Triggers are not available") },
    update: fn(_, _) { Error("Triggers are not available") },
    list: fn() { [] },
  )
}

fn no_subagent(_task) {
  Error("Delegation is not available")
}

/// Access to the workspace's file system, paths are absolute.
pub type Files {
  Files(
    read: fn(String) -> Result(BitArray, String),
    read_directory: fn(String) ->
      Result(List(#(String, read_directory.Entry)), String),
    update: fn(files.Operation, String) -> Result(Nil, String),
  )
}

/// Files for a program run by `by`, changes are reported as made by `by`.
pub fn files(system: Subject(files.Message), by: String) -> Files {
  Files(
    read: fn(path) { files.call(system, files.Read(path, _)) },
    read_directory: fn(path) {
      files.call(system, files.ReadDirectory(path, _))
    },
    update: fn(operation, path) {
      files.call(system, files.Update(operation, path, by, _))
    },
  )
}

/// No file system, every file effect fails.
pub fn no_files() -> Files {
  Files(
    read: fn(_) { Error("There is no file system") },
    read_directory: fn(_) { Error("There is no file system") },
    update: fn(_, _) { Error("There is no file system") },
  )
}

/// A host for programs run from a channel, they have no access to secrets.
/// Delegation is added when the channel shell is prepared, see `cloud/shell`.
pub fn channel_host(
  post: fn(String) -> Result(String, String),
  files: Files,
  triggers: Triggers,
) -> Host {
  Host(
    post:,
    secret: fn(_) { Error("Secrets are not available") },
    files:,
    triggers:,
    subagent: no_subagent,
  )
}

/// A host with only secrets, for evaluating configuration.
pub fn configuration_host(
  secret: fn(String) -> Result(String, String),
) -> Host {
  Host(
    post: fn(_) { Error("Configuration cannot post") },
    secret:,
    files: no_files(),
    triggers: no_triggers(),
    subagent: no_subagent,
  )
}

pub type Policy =
  policy.Policy(Effect, Meta)

const computer_effects = [
  "AppendFile", "CWD", "DecodeJSON", "DeleteFile", "Env", "Fetch", "Flip",
  "Hash", "MakeDirectory", "Now", "Random", "ReadDirectory", "ReadFile", "Sleep",
  "StandardError", "StandardOut", "WriteFile",
]

/// Every effect available on the cloud.
pub fn harness() -> interface.Harness(Effect, Meta) {
  computer.effects()
  |> interface.take(computer_effects)
  |> list.map(touch_grass.map(_, Computer))
  |> list.append([
    post(),
    add_trigger(),
    trigger_update("StopTrigger", StopTrigger),
    trigger_update("StartTrigger", StartTrigger),
    trigger_update("DeleteTrigger", DeleteTrigger),
    list_triggers(),
    delegate_interface(),
  ])
}

fn add_trigger() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "AddTrigger",
    lift_type: trigger.type_(),
    lower_type: t.result(t.unit, t.String),
    decode: cast.map(trigger.decode, AddTrigger),
  )
}

fn trigger_update(name, effect) -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name:,
    lift_type: t.String,
    lower_type: t.result(t.unit, t.String),
    decode: cast.map(cast.as_string, effect),
  )
}

fn list_triggers() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "ListTriggers",
    lift_type: t.unit,
    lower_type: t.List(t.String),
    decode: cast.as_unit(_, ListTriggers),
  )
}

fn delegate_interface() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "Delegate",
    lift_type: t.String,
    lower_type: t.result(t.String, t.String),
    decode: cast.map(cast.as_string, Delegate),
  )
}

/// Every effect available to the workspace configuration, the channel effects and `Secret`.
pub fn configuration_harness() -> interface.Harness(Effect, Meta) {
  list.append(harness(), [secret()])
}

fn secret() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "Secret",
    lift_type: t.String,
    lower_type: t.result(t.String, t.String),
    decode: cast.map(cast.as_string, Secret),
  )
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
  #("AddTrigger", policy.PolicyField("add_trigger")),
  #("AppendFile", policy.PolicyField("append_file")),
  #("CWD", policy.PolicyField("cwd")),
  #("DecodeJSON", policy.Unchecked),
  #("Delegate", policy.PolicyField("delegate")),
  #("DeleteFile", policy.PolicyField("delete_file")),
  #("DeleteTrigger", policy.PolicyField("delete_trigger")),
  #("Env", policy.PolicyField("env")),
  #("Fetch", policy.PolicyField("fetch")),
  #("Flip", policy.PolicyField("flip")),
  #("Hash", policy.Unchecked),
  #("ListTriggers", policy.PolicyField("list_triggers")),
  #("MakeDirectory", policy.PolicyField("make_directory")),
  #("Now", policy.PolicyField("now")),
  #("Post", policy.PolicyField("post")),
  #("Random", policy.PolicyField("random")),
  #("ReadDirectory", policy.PolicyField("read_directory")),
  #("ReadFile", policy.PolicyField("read_file")),
  #("Sleep", policy.PolicyField("sleep")),
  #("StartTrigger", policy.PolicyField("start_trigger")),
  #("StandardError", policy.PolicyField("standard_error")),
  #("StandardOut", policy.PolicyField("standard_out")),
  #("StopTrigger", policy.PolicyField("stop_trigger")),
  #("WriteFile", policy.PolicyField("write_file")),
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

/// A policy that performs every effect available to channels without a gate.
pub fn unrestricted() -> Policy {
  without_gates(harness())
}

/// The policy the trusted workspace configuration is evaluated with.
pub fn configuration() -> Policy {
  without_gates(configuration_harness())
}

fn without_gates(harness: interface.Harness(Effect, Meta)) -> Policy {
  harness
  |> list.map(fn(interface) {
    #(interface.name, policy.Interface(interface, policy.Unrestricted))
  })
  |> dict.from_list
}

pub fn output_text(output: Output) -> String {
  case output {
    StandardOut(text) -> text
    StandardError(text) -> text
  }
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
  run_with_lookup(code, scope, policy, host, state, fn(reference, state) {
    program_reference(reference, state, policy, host, [])
  })
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

/// Run captured scripts with the same session import resolver as source programs.
pub fn run_expression(
  source: ir.Node(Meta),
  scope: List(#(String, Value)),
  policy: Policy,
  host: Host,
  state: State,
) -> #(Run, State) {
  loop(
    expression.execute(source, scope),
    state,
    policy,
    host,
    [],
    fn(reference, state) {
      program_reference(reference, state, policy, host, [])
    },
  )
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
      let lift = absolute_paths(label, lift)
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

/// Policies decide on absolute file paths, relative paths are from the root.
fn absolute_paths(label, lift) {
  case label, lift {
    "ReadFile", v.Record(fields)
    | "WriteFile", v.Record(fields)
    | "AppendFile", v.Record(fields)
    ->
      case dict.get(fields, "path") {
        Ok(v.String(path)) ->
          v.Record(dict.insert(fields, "path", v.String(files.normalize(path))))
        _ -> lift
      }
    "DeleteFile", v.String(path)
    | "MakeDirectory", v.String(path)
    | "ReadDirectory", v.String(path)
    -> v.String(files.normalize(path))
    _, _ -> lift
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
    Secret(name) -> Ok(#(result_string(host.secret(name)), []))
    AddTrigger(trigger) -> Ok(#(result_unit(host.triggers.add(trigger)), []))
    StopTrigger(name) ->
      Ok(#(result_unit(host.triggers.update(name, Stop)), []))
    StartTrigger(name) ->
      Ok(#(result_unit(host.triggers.update(name, Start)), []))
    DeleteTrigger(name) ->
      Ok(#(result_unit(host.triggers.update(name, Delete)), []))
    ListTriggers -> {
      let described = list.map(host.triggers.list(), trigger.describe)
      Ok(#(v.LinkedList(list.map(described, v.String)), []))
    }
    Delegate(task) -> Ok(#(result_string(host.subagent(task)), []))
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
        computer.Cwd -> Ok(#(v.ok(v.String("/")), []))
        computer.ReadFile(read_file.Input(path:, offset:, limit:)) ->
          host.files.read(path)
          |> result.map(files.slice(_, offset, limit))
          |> read_file.encode
          |> no_output
        computer.ReadDirectory(path:) ->
          host.files.read_directory(path) |> read_directory.encode |> no_output
        computer.WriteFile(write_file.Input(path:, contents:)) ->
          host.files.update(files.Write(contents), path)
          |> write_file.encode
          |> no_output
        computer.AppendFile(append_file.Input(path:, contents:)) ->
          host.files.update(files.Append(contents), path)
          |> append_file.encode
          |> no_output
        computer.DeleteFile(path:) ->
          host.files.update(files.Delete, path)
          |> delete_file.encode
          |> no_output
        computer.MakeDirectory(path:) ->
          host.files.update(files.MakeDirectory, path)
          |> make_directory.encode
          |> no_output
        computer.Sleep(milliseconds) -> {
          process.sleep(int.max(0, milliseconds))
          Ok(#(sleep.encode(Nil), []))
        }
        _ -> Error("Effect not implemented on the cloud")
      }
  }
}

fn no_output(value) {
  Ok(#(value, []))
}

fn result_unit(result) {
  case result {
    Ok(Nil) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
}

fn result_string(result) {
  case result {
    Ok(value) -> v.ok(v.String(value))
    Error(reason) -> v.error(v.String(reason))
  }
}

/// Resolve file imports only through the session filesystem and its ReadFile gate.
fn program_reference(reference, state: State, policy, host, visiting) {
  case reference {
    ir.Relative(path) -> {
      let path = files.normalize(path)
      let #(loaded, state) = read_import(path, policy, host, state)
      let #(result, state) = case loaded {
        Error(reason) -> #(Error(reason), state)
        Ok(#(bytes, file)) ->
          case list.contains(visiting, file) {
            True -> #(Error("Cyclic session import: " <> file), state)
            False ->
              case parse_module(bytes, file) {
                Error(reason) -> #(Error(reason), state)
                Ok(source) -> {
                  let source = anchor_imports(source, file)
                  module_loop(
                    expression.execute(source, []),
                    state,
                    fn(ref, state) {
                      program_reference(ref, state, policy, host, [
                        file,
                        ..visiting
                      ])
                    },
                  )
                }
              }
          }
      }
      #(result, state.cache)
    }
    _ -> lookup_hub(reference, state)
  }
}

/// Anchor imports inside returned closures as well as immediate module imports.
fn anchor_imports(source, file) {
  ir.rewrite(source, fn(node) {
    let node = case node.0 {
      ir.Reference(ir.Relative(path)) -> {
        let path = case filepath.is_absolute(path) {
          True -> files.normalize(path)
          False ->
            files.normalize(filepath.join(filepath.directory_name(file), path))
        }
        #(ir.Reference(ir.Relative(path)), node.1)
      }
      _ -> node
    }
    continuation.return(node)
  })(fn(node) { node })
}

fn read_import(path, policy, host: Host, state: State) {
  let input =
    v.Record(
      dict.from_list([
        #("path", v.String(path)),
        #("offset", v.Integer(0)),
        #("limit", v.Integer(100_000_000)),
      ]),
    )
  let #(action, state) = decide(policy, "ReadFile", input, #(0, 0), state)
  let loaded = case action {
    policy.Perform(interface, input) -> {
      use effect <- result.try(
        interface.decode(input) |> result.map_error(simple_debug.describe),
      )
      case effect {
        Computer(computer.ReadFile(read_file.Input(path:, offset:, limit:))) ->
          host.files.read(path)
          |> result.map(fn(bytes) { #(files.slice(bytes, offset, limit), path) })
        _ -> Error("Import policy did not return a ReadFile request")
      }
    }
    policy.Resume(v.Tagged("Ok", v.Binary(bytes))) -> Ok(#(bytes, path))
    policy.Resume(v.Tagged("Error", v.String(reason))) -> Error(reason)
    policy.Resume(_) -> Error("Import policy must return file bytes")
    policy.Unavailable -> Error("Effect ReadFile is not allowed by policy")
    policy.Failed(#(reason, _, _, _)) ->
      Error("Policy failed: " <> simple_debug.describe(reason))
  }
  #(loaded, state)
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
