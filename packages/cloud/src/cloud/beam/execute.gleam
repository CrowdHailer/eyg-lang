//// Run EYG code on the cloud platform.
////
//// This module is similar to loam/execute BUT it's not the beam plaform instead it's the cloud platform.
//// Every effect is decided by a policy, see `overlay/policy`.
//// Effects that need the cloud's services, such as posting to a channel, are implemented by a `Host`.

import cloud/artifacts
import cloud/files
import cloud/operation
import cloud/system
import cloud/tracing
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
  /// Read the logged events of a connection, newest first.
  Events(connection: String)
  /// An operation of the configuration API, see `cloud/operation`.
  Operate(operation.Operation)
  /// Run the rest of a web shell's programs as a channel of a workspace.
  Bind(workspace: String, channel: String)
  Unbind
  /// Send a message to the program's session on a cron schedule.
  Cron(name: String, schedule: String, message: String)
  /// Send a message to the program's session once, after a number of milliseconds.
  Timeout(name: String, after: Int, message: String)
  CancelSchedule(name: String)
  /// Save a new version of an artifact owned by the program's channel.
  SaveArtifact(name: String, bundle: artifacts.Bundle)
  /// Let any channel in the workspace save versions of an artifact.
  ShareArtifact(name: String)
}

/// Implementations of effects that need the cloud's services.
pub type Host {
  Host(
    post: fn(String) -> Result(String, String),
    secret: fn(String) -> Result(String, String),
    files: Files,
    triggers: Triggers,
    /// Run a subagent with a task, its spans are children of the given span.
    subagent: fn(String, Option(tracing.Context)) -> Result(String, String),
    schedules: Schedules,
    artifacts: Artifacts,
    /// The logged events of a connection, newest first.
    events: fn(String) -> Result(List(Value), String),
    /// Perform an operation of the configuration API.
    api: fn(operation.Operation) -> Result(Value, String),
    /// Bind a web shell to a channel, `None` unbinds it. Only web shells can bind.
    bind: fn(Option(#(String, String))) -> Result(Nil, String),
    /// The span programs run with this host belong to, see `cloud/tracing`.
    trace: Option(tracing.Context),
  )
}

fn no_api(_operation) {
  Error("The configuration API is not available")
}

fn no_bind(_channel) {
  Error("Only web shells can bind to a channel")
}

fn no_events(_connection) {
  Error("Events are not available")
}

/// The artifacts of the program's channel.
pub type Artifacts {
  Artifacts(
    save: fn(String, artifacts.Bundle) -> Result(artifacts.Saved, String),
    share: fn(String) -> Result(String, String),
  )
}

/// Save and share artifacts as `channel`.
pub fn artifacts(
  store: Subject(artifacts.Message),
  channel: artifacts.Channel,
) -> Artifacts {
  Artifacts(
    save: fn(name, bundle) {
      artifacts.call(store, artifacts.Save(name, bundle, channel, _))
    },
    share: fn(name) { artifacts.call(store, artifacts.Share(name, channel, _)) },
  )
}

pub fn no_artifacts() -> Artifacts {
  Artifacts(
    save: fn(_, _) { Error("Artifacts are not available") },
    share: fn(_) { Error("Artifacts are not available") },
  )
}

/// Messages scheduled for the program's session, see `cloud/cron` for schedules.
pub type Schedules {
  Schedules(
    cron: fn(String, String, String) -> Result(Nil, String),
    timeout: fn(String, Int, String) -> Result(Nil, String),
    cancel: fn(String) -> Result(Nil, String),
  )
}

pub fn no_schedules() -> Schedules {
  Schedules(
    cron: fn(_, _, _) { Error("Schedules are not available") },
    timeout: fn(_, _, _) { Error("Schedules are not available") },
    cancel: fn(_) { Error("Schedules are not available") },
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

fn no_subagent(_task, _trace) {
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
  schedules: Schedules,
  artifacts: Artifacts,
) -> Host {
  Host(
    post:,
    secret: fn(_) { Error("Secrets are not available") },
    files:,
    triggers:,
    subagent: no_subagent,
    schedules:,
    artifacts:,
    events: no_events,
    api: no_api,
    bind: no_bind,
    trace: option.None,
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
    schedules: no_schedules(),
    artifacts: no_artifacts(),
    events: no_events,
    api: no_api,
    bind: no_bind,
    trace: option.None,
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
    events(),
    cron(),
    timeout(),
    cancel_schedule(),
    artifact(),
    share_artifact(),
    bind(),
    unbind(),
    ..list.map(operation.specs(), operation_interface)
  ])
}

fn operation_interface(
  spec: operation.Spec,
) -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: spec.label,
    lift_type: spec.lift,
    lower_type: spec.lower,
    decode: fn(value) { spec.decode(value) |> result.map(Operate) },
  )
}

fn bind() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "Bind",
    lift_type: t.record([#("workspace", t.String), #("channel", t.String)]),
    lower_type: t.result(t.unit, t.String),
    decode: fn(value) {
      use workspace <- result.try(cast.field("workspace", cast.as_string, value))
      use channel <- result.map(cast.field("channel", cast.as_string, value))
      Bind(workspace, channel)
    },
  )
}

fn unbind() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "Unbind",
    lift_type: t.unit,
    lower_type: t.result(t.unit, t.String),
    decode: cast.as_unit(_, Unbind),
  )
}

fn artifact() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "Artifact",
    lift_type: t.record([
      #("name", t.String),
      #(
        "bundle",
        t.List(
          t.record([
            #("path", t.String),
            #("media_type", t.String),
            #("content", t.Binary),
          ]),
        ),
      ),
    ]),
    lower_type: t.result(
      t.record([#("version", t.Integer), #("url", t.String)]),
      t.String,
    ),
    decode: fn(value) {
      use name <- result.try(cast.field("name", cast.as_string, value))
      use bundle <- result.try(cast.field(
        "bundle",
        cast.as_list_of(_, decode_file),
        value,
      ))
      Ok(SaveArtifact(name:, bundle:))
    },
  )
}

fn decode_file(value) {
  use path <- result.try(cast.field("path", cast.as_string, value))
  use media_type <- result.try(cast.field("media_type", cast.as_string, value))
  use content <- result.try(cast.field("content", cast.as_binary, value))
  Ok(artifacts.File(path:, media_type:, content:))
}

fn share_artifact() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "ShareArtifact",
    lift_type: t.String,
    lower_type: t.result(t.String, t.String),
    decode: cast.map(cast.as_string, ShareArtifact),
  )
}

fn cron() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "Cron",
    lift_type: t.record([
      #("name", t.String),
      #("schedule", t.String),
      #("message", t.String),
    ]),
    lower_type: t.result(t.unit, t.String),
    decode: fn(value) {
      use name <- result.try(cast.field("name", cast.as_string, value))
      use schedule <- result.try(cast.field("schedule", cast.as_string, value))
      use message <- result.try(cast.field("message", cast.as_string, value))
      Ok(Cron(name:, schedule:, message:))
    },
  )
}

fn timeout() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "Timeout",
    lift_type: t.record([
      #("name", t.String),
      #("after", t.Integer),
      #("message", t.String),
    ]),
    lower_type: t.result(t.unit, t.String),
    decode: fn(value) {
      use name <- result.try(cast.field("name", cast.as_string, value))
      use after <- result.try(cast.field("after", cast.as_integer, value))
      use message <- result.try(cast.field("message", cast.as_string, value))
      Ok(Timeout(name:, after:, message:))
    },
  )
}

fn cancel_schedule() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "CancelSchedule",
    lift_type: t.String,
    lower_type: t.result(t.unit, t.String),
    decode: cast.map(cast.as_string, CancelSchedule),
  )
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

fn events() -> interface.Interface(Effect, Meta) {
  interface.Interface(
    name: "Events",
    lift_type: t.String,
    lower_type: t.result(t.List(trigger.event_type()), t.String),
    decode: cast.map(cast.as_string, Events),
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
  #("Bind", policy.PolicyField("bind")),
  #("Artifact", policy.PolicyField("artifact")),
  #("CancelSchedule", policy.PolicyField("cancel_schedule")),
  #("Cron", policy.PolicyField("cron")),
  #("CWD", policy.PolicyField("cwd")),
  #("DecodeJSON", policy.Unchecked),
  #("Delegate", policy.PolicyField("delegate")),
  #("DeleteFile", policy.PolicyField("delete_file")),
  #("DeleteTrigger", policy.PolicyField("delete_trigger")),
  #("Env", policy.PolicyField("env")),
  #("Events", policy.PolicyField("events")),
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
  #("ShareArtifact", policy.PolicyField("share_artifact")),
  #("Sleep", policy.PolicyField("sleep")),
  #("StartTrigger", policy.PolicyField("start_trigger")),
  #("StandardError", policy.PolicyField("standard_error")),
  #("StandardOut", policy.PolicyField("standard_out")),
  #("StopTrigger", policy.PolicyField("stop_trigger")),
  #("Timeout", policy.PolicyField("timeout")),
  #("Unbind", policy.PolicyField("unbind")),
  #("WriteFile", policy.PolicyField("write_file")),
  ..operation_rules
]

const operation_rules = [
  #("Workspaces", policy.PolicyField("workspaces")),
  #("WorkspaceSource", policy.PolicyField("workspace_source")),
  #("SetWorkspaceSource", policy.PolicyField("set_workspace_source")),
  #("Channels", policy.PolicyField("channels")),
  #("Connections", policy.PolicyField("connections")),
  #("WorkspaceTriggers", policy.PolicyField("workspace_triggers")),
  #("Secrets", policy.PolicyField("secrets")),
  #("SetSecret", policy.PolicyField("set_secret")),
  #("DeleteSecret", policy.PolicyField("delete_secret")),
  #("Users", policy.PolicyField("users")),
  #("Shells", policy.PolicyField("shells")),
  #("SetUserShell", policy.PolicyField("set_user_shell")),
  #("Traces", policy.PolicyField("traces")),
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
  run_with_lookup(code, scope, policy, host, state, fn(reference, state, host) {
    program_reference(reference, state, policy, host, [])
  })
}

/// Only trusted configuration resolves imports on the host filesystem.
/// Channel programs, agent actions and web/API scripts always use `run`.
pub fn run_configuration(code, policy, host, state) {
  run_with_lookup(code, [], policy, host, state, fn(reference, state, _host) {
    lookup(reference, state)
  })
}

fn run_with_lookup(code, scope, policy, host: Host, state: State, resolve) {
  let scope = list.append(scope, [#("cloud", platform())])
  let span = tracing.start("eyg.run", host.trace, [])
  let host = Host(..host, trace: option.Some(tracing.context(span)))
  let resolve = fn(reference, state) { resolve(reference, state, host) }
  let #(run, state) = case parser.all_from_string(code) {
    Error(reason) -> #(Run(Error(parser.format_error(reason, code)), []), state)
    Ok(source) ->
      loop(expression.execute(source, scope), state, policy, host, [], resolve)
  }
  finish(span, run, state)
}

/// Run an expression, for example a captured trigger script applied to its event.
pub fn run_expression(
  expression: ir.Node(Meta),
  scope: List(#(String, Value)),
  policy: Policy,
  host: Host,
  state: State,
) -> #(Run, State) {
  let span = tracing.start("eyg.run", host.trace, [])
  let host = Host(..host, trace: option.Some(tracing.context(span)))
  let #(run, state) =
    loop(
      expression.execute(expression, scope),
      state,
      policy,
      host,
      [],
      fn(reference, state) {
        program_reference(reference, state, policy, host, [])
      },
    )
  finish(span, run, state)
}

fn finish(span, run: Run, state) {
  let error = case run.result {
    Ok(_) -> option.None
    Error(reason) -> option.Some(reason)
  }
  tracing.end(span, [], error)
  #(run, state)
}

/// Record a span for an effect, how the policy decided and whether it failed.
fn effect_span(label, host: Host, then) {
  let span =
    tracing.start("eyg.effect." <> label, host.trace, [
      #("eyg.effect.name", tracing.text(label)),
    ])
  let #(decision, failure, result) =
    then(Host(..host, trace: option.Some(tracing.context(span))))
  tracing.end(span, [#("eyg.policy.decision", tracing.text(decision))], failure)
  result
}

/// An `Error` reply is a failed effect, though the program can recover from it.
fn failure(value) {
  case value {
    v.Tagged("Error", v.String(reason)) -> option.Some(reason)
    v.Tagged("Error", reason) -> option.Some(simple_debug.inspect(reason))
    _ -> option.None
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
      let lift = absolute_paths(label, lift)
      let #(action, state) = decide(policy, label, lift, meta, state)
      // Each effect is a span, the program continues after it ends.
      let next = {
        use host <- effect_span(label, host)
        case action {
          policy.Perform(interface, input) ->
            case interface.decode(input) {
              Ok(effect) ->
                case perform(effect, host) {
                  Ok(#(value, printed)) -> #(
                    "pass",
                    failure(value),
                    Ok(#(value, printed)),
                  )
                  Error(reason) -> #("pass", option.Some(reason), Error(reason))
                }
              Error(reason) -> {
                let reason = simple_debug.describe(reason)
                #("pass", option.Some(reason), Error(reason))
              }
            }
          policy.Resume(value) -> #("mock", failure(value), Ok(#(value, [])))
          policy.Failed(#(reason, _, _, _)) -> {
            let reason = "Policy failed: " <> simple_debug.describe(reason)
            #("failed", option.Some(reason), Error(reason))
          }
          policy.Unavailable -> {
            let reason = "Effect " <> label <> " is not allowed by policy"
            #("unavailable", option.Some(reason), Error(reason))
          }
        }
      }
      case next {
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
    Delegate(task) -> Ok(#(result_string(host.subagent(task, host.trace)), []))
    Operate(operation) ->
      case host.api(operation) {
        Ok(value) -> v.ok(value)
        Error(reason) -> v.error(v.String(reason))
      }
      |> no_output
    Bind(workspace, channel) ->
      Ok(#(result_unit(host.bind(option.Some(#(workspace, channel)))), []))
    Unbind -> Ok(#(result_unit(host.bind(option.None)), []))
    Events(connection) ->
      case host.events(connection) {
        Ok(events) -> v.ok(v.LinkedList(events))
        Error(reason) -> v.error(v.String(reason))
      }
      |> no_output
    Cron(name:, schedule:, message:) ->
      Ok(#(result_unit(host.schedules.cron(name, schedule, message)), []))
    Timeout(name:, after:, message:) ->
      Ok(#(result_unit(host.schedules.timeout(name, after, message)), []))
    CancelSchedule(name) -> Ok(#(result_unit(host.schedules.cancel(name)), []))
    SaveArtifact(name:, bundle:) ->
      case host.artifacts.save(name, bundle) {
        Ok(artifacts.Saved(version:, url:)) ->
          v.ok(
            v.Record(
              dict.from_list([
                #("version", v.Integer(version)),
                #("url", v.String(url)),
              ]),
            ),
          )
        Error(reason) -> v.error(v.String(reason))
      }
      |> no_output
    ShareArtifact(name) -> Ok(#(result_string(host.artifacts.share(name)), []))
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
  let loaded = {
    use host <- effect_span("ReadFile", host)
    let #(decision, loaded) = case action {
      policy.Perform(interface, input) -> {
        let loaded = {
          use effect <- result.try(
            interface.decode(input) |> result.map_error(simple_debug.describe),
          )
          case effect {
            Computer(computer.ReadFile(read_file.Input(path:, offset:, limit:))) ->
              host.files.read(path)
              |> result.map(fn(bytes) {
                #(files.slice(bytes, offset, limit), path)
              })
            _ -> Error("Import policy did not return a ReadFile request")
          }
        }
        #("pass", loaded)
      }
      policy.Resume(v.Tagged("Ok", v.Binary(bytes))) -> #(
        "mock",
        Ok(#(bytes, path)),
      )
      policy.Resume(v.Tagged("Error", v.String(reason))) -> #(
        "mock",
        Error(reason),
      )
      policy.Resume(_) -> #(
        "failed",
        Error("Import policy must return file bytes"),
      )
      policy.Unavailable -> #(
        "unavailable",
        Error("Effect ReadFile is not allowed by policy"),
      )
      policy.Failed(#(reason, _, _, _)) -> #(
        "failed",
        Error("Policy failed: " <> simple_debug.describe(reason)),
      )
    }
    let failure = case loaded {
      Ok(_) -> option.None
      Error(reason) -> option.Some(reason)
    }
    #(decision, failure, loaded)
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
