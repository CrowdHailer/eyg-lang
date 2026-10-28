//// Run EYG programs for an opencode agent, every effect is decided by a policy.
////
//// The standalone runtime is shared by the host integrations. Host callbacks,
//// including Task, are gated by the same policy as computer effects.

import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import filepath
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import loam/execute
import loam/platform/computer
import loam/source
import loam/system
import ogre/origin
import opencode_plugin/convert
import opencode_plugin/policy.{type Policy}
import overlay/agent
import plinthx/javascript/foreign
import plinthx/javascript/string as native_string
import touch_grass/file_system/cwd
import touch_grass/harness/computer as harness
import touch_grass/standard_error
import touch_grass/standard_in
import touch_grass/standard_out

/// The evaluated configuration file.
pub type Config {
  Config(
    policy: Policy,
    context: execute.Value,
    agents: Dict(String, execute.Value),
    readme: String,
  )
}

/// An effect implemented by the host in JavaScript.
/// The handler receives the lift converted to JavaScript and the raw EYG value.
/// Its result is returned to the program as `Ok(value)`, a thrown error as `Error(message)`.
pub type Host {
  Host(label: String, lift: String, lower: String, handler: Dynamic)
}

pub fn host(label, lift, lower, handler) {
  Host(label:, lift:, lower:, handler:)
}

fn hub_origin() {
  origin.https("eyg.run")
}

fn new_state() {
  execute.State(hub_origin(), cache.empty(), None)
}

// ---------------- configuration

/// Evaluate a configuration file, it may perform any effect as it is written by the user.
/// The file returns a record with a `policy` field and optional `context` and `agents` fields.
pub fn load(path: String) -> Promise(Result(Config, String)) {
  use value <- promise.map(evaluate(path))
  result.try(value, cast_config)
}

/// Evaluate a file written by the user, it may perform any effect.
pub fn evaluate(path: String) -> Promise(Result(execute.Value, String)) {
  let input = source.File(path)
  use code <- promise.await(system.run(source.read_input(input)))
  case code {
    Ok(code) -> evaluate_source(code, path)
    Error(reason) -> promise.resolve(Error(reason))
  }
}

/// Evaluate source code as if it was in the file at `path`, relative imports are resolved from there.
pub fn evaluate_source(
  code: String,
  path: String,
) -> Promise(Result(execute.Value, String)) {
  case source.parse_input(code, source.File(path)) {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(code) -> {
      use #(result, _state) <- promise.map(
        system.run(execute.block(code, [], new_state())),
      )
      case result {
        Ok(#(Some(value), _)) -> Ok(value)
        Ok(#(None, _)) -> Error(path <> " has no final expression")
        Error(#(reason, location, _, k)) ->
          Error(execute.render_error(reason, location, k, path))
      }
    }
  }
}

/// Load configuration from source code, used for a default configuration.
pub fn load_source(code: String, path: String) {
  use value <- promise.map(evaluate_source(code, path))
  result.try(value, cast_config)
}

fn cast_config(value) {
  use policy <- result.try(case cast.field("policy", Ok, value) {
    Ok(policy) -> policy.from_value(policy)
    Error(_) -> Error("the configuration must have a policy field")
  })
  let context = cast.field("context", Ok, value) |> result.unwrap(v.unit())
  let agents =
    cast.field("agents", cast.as_record, value) |> result.unwrap(dict.new())
  let readme =
    cast.field("readme", cast.as_string, context) |> result.unwrap("")
  Ok(Config(policy:, context:, agents:, readme:))
}

pub fn config_policy(config: Config) {
  config.policy
}

pub fn config_context(config: Config) {
  config.context
}

pub fn config_readme(config: Config) {
  config.readme
}

/// The policy a user configured for a named agent, it replaces the parent policy.
pub fn agent_policy(config: Config, name: String) -> Result(Policy, Nil) {
  case dict.get(config.agents, name) {
    Ok(value) -> policy.from_value(value) |> result.replace_error(Nil)
    Error(Nil) -> Error(Nil)
  }
}

pub fn restrict(parent: Policy, child: execute.Value) {
  policy.restrict(parent, child)
}

pub fn replace(child: execute.Value) {
  policy.from_value(child)
}

/// A field of a raw EYG value passed to a host handler.
pub fn field(value: execute.Value, name: String) -> Result(execute.Value, Nil) {
  cast.field(name, Ok, value) |> result.replace_error(Nil)
}

pub fn inspect(value: execute.Value) -> String {
  agent.inspect_result(value)
}

// ---------------- description

/// Describe the effects a policy makes available, with their types.
pub fn describe(policy: Policy, hosts: List(Host)) -> String {
  let computer =
    computer.effects()
    |> list.filter(fn(i) { available(policy, i.name) })
    |> list.map(agent.describe_effect)
  let hosts =
    hosts
    |> list.filter(fn(h) { available(policy, h.label) })
    |> list.map(fn(h) {
      h.label <> ": " <> h.lift <> " -> Result(" <> h.lower <> ", String)"
    })
  list.append(computer, hosts) |> list.sort(string.compare) |> string.join("\n")
}

fn available(policy, label) {
  case policy.access(policy, label) {
    policy.Unavailable -> False
    _ -> label != "Exit" && label != "StandardIn"
  }
}

pub fn fields(policy: Policy) -> List(String) {
  policy.fields(policy)
}

// ---------------- running

pub type Report {
  Report(ok: Bool, output: String, value: String, effects: List(String))
}

pub fn report_ok(report: Report) {
  report.ok
}

pub fn report_text(report: Report) {
  let Report(output:, value:, ..) = report
  case output {
    "" -> value
    _ -> "Output:\n" <> output <> "\nResult:\n" <> value
  }
}

pub fn report_effects(report: Report) {
  report.effects
}

type Run {
  Run(
    policy: Policy,
    hosts: List(Host),
    directory: String,
    output: List(String),
    effects: List(String),
    state: execute.State,
  )
}

/// Run a program, `context` is in scope.
/// Relative paths are resolved from `directory`.
pub fn run(
  code: String,
  policy: Policy,
  context: execute.Value,
  directory: String,
  hosts: List(Host),
) -> Promise(Report) {
  let origin = source.Disk(filepath.join(directory, "eyg"))
  case source.parse(code, origin) {
    Error(reason) -> promise.resolve(Report(False, "", reason, []))
    Ok(code) -> {
      let run = Run(policy, hosts, directory, [], [], new_state())
      use #(result, run) <- promise.map(loop(
        block.execute(code, [#("context", context)]),
        run,
      ))
      let output = run.output |> list.reverse |> string.concat
      let effects = list.reverse(run.effects)
      case result {
        Ok(#(Some(value), _)) ->
          Report(True, output, agent.inspect_result(value), effects)
        Ok(#(None, _)) -> Report(True, output, "", effects)
        Error(#(reason, location, _env, k)) ->
          Report(
            False,
            output,
            denied(reason, policy, hosts)
              <> execute.render_error(reason, location, k, directory),
            effects,
          )
      }
    }
  }
}

fn loop(return, run: Run) {
  case return {
    Ok(value) -> promise.resolve(#(Ok(value), run))
    Error(#(reason, meta, env, k)) as error ->
      case reason {
        break.UnhandledEffect(label, lift) -> {
          let run = Run(..run, effects: [label, ..run.effects])
          use #(result, run) <- promise.await(decide(label, lift, meta, run))
          case result {
            Ok(value) -> loop(block.resume(value, env, k), run)
            Error(reason) ->
              promise.resolve(#(Error(#(reason, meta, env, k)), run))
          }
        }
        break.UndefinedReference(reference) -> {
          use #(result, run) <- promise.await(lookup(reference, meta, run))
          case result {
            Ok(value) -> loop(block.resume(value, env, k), run)
            Error(reason) ->
              promise.resolve(#(Error(#(reason, meta, env, k)), run))
          }
        }
        _ -> promise.resolve(#(error, run))
      }
  }
}

/// File paths are made absolute before a gate sees them, so policies can compare them with roots.
fn absolute(label, lift, directory) {
  let resolve = fn(path) {
    system.resolve_relative(directory, path)
    |> result.replace_error(abort("invalid filesystem path"))
  }
  case label, lift {
    "ReadDirectory", v.String(path)
    | "DeleteFile", v.String(path)
    | "MakeDirectory", v.String(path)
    -> resolve(path) |> result.map(v.String)
    "ReadFile", v.Record(fields)
    | "WriteFile", v.Record(fields)
    | "AppendFile", v.Record(fields)
    | "Mount", v.Record(fields)
    | "Read", v.Record(fields)
    | "Write", v.Record(fields)
    | "Edit", v.Record(fields)
    | "Grep", v.Record(fields)
    | "Glob", v.Record(fields)
    ->
      list.try_fold(["path", "file_path"], fields, fn(fields, name) {
        case dict.get(fields, name) {
          Ok(v.String(path)) ->
            resolve(path)
            |> result.map(fn(path) { dict.insert(fields, name, v.String(path)) })
          _ -> Ok(fields)
        }
      })
      |> result.map(v.Record)
    _, _ -> Ok(lift)
  }
}

fn decide(label, lift, meta: source.Location, run: Run) {
  case absolute(label, lift, run.directory) {
    Error(reason) -> promise.resolve(#(Error(reason), run))
    Ok(lift) -> decide_absolute(label, lift, meta, run)
  }
}

fn decide_absolute(label, lift, meta: source.Location, run: Run) {
  case policy.access(run.policy, label) {
    policy.Unavailable ->
      promise.resolve(#(Error(unavailable(label, lift)), run))
    policy.Open -> perform(label, lift, meta, run)
    policy.Gated(gates) -> {
      use #(decision, run) <- promise.await(gate(label, gates, lift, meta, run))
      case decision {
        Ok(policy.Pass(lift)) -> perform(label, lift, meta, run)
        Ok(policy.Mock(value)) -> promise.resolve(#(Ok(value), run))
        Error(reason) -> promise.resolve(#(Error(reason), run))
      }
    }
  }
}

fn unavailable(label, lift) {
  break.UnhandledEffect(label, lift)
}

/// Run each gate in turn, a `Pass` value is the input to the next gate.
fn gate(label, gates, lift, meta, run: Run) {
  case absolute(label, lift, run.directory) {
    Error(reason) -> promise.resolve(#(Error(reason), run))
    Ok(lift) -> gate_absolute(label, gates, lift, meta, run)
  }
}

fn gate_absolute(label, gates, lift, meta, run: Run) {
  case gates {
    [] -> promise.resolve(#(Ok(policy.Pass(lift)), run))
    [first, ..rest] -> {
      // A gate is pure: load its referenced helpers in the trusted configuration.
      case expression.call(first, [#(lift, meta)]) {
        Ok(value) ->
          case policy.decision(value) {
            Ok(policy.Pass(lift)) -> gate(label, rest, lift, meta, run)
            Ok(policy.Mock(value)) ->
              promise.resolve(#(Ok(policy.Mock(value)), run))
            Error(Nil) ->
              promise.resolve(#(
                Error(break.IncorrectTerm("Pass(lift) or Mock(lower)", value)),
                run,
              ))
          }
        Error(#(reason, _, _, _)) -> promise.resolve(#(Error(reason), run))
      }
    }
  }
}

fn perform(label, lift, meta: source.Location, run: Run) {
  case list.find(run.hosts, fn(h) { h.label == label }) {
    Ok(host) -> {
      use result <- promise.map(call_host(
        host.handler,
        convert.to_js(lift),
        lift,
      ))
      let value = case result {
        Ok(value) -> v.ok(convert.from_js(value))
        Error(reason) -> v.error(v.String(reason))
      }
      #(Ok(value), run)
    }
    Error(Nil) ->
      case computer.cast(label, lift) {
        Error(reason) -> promise.resolve(#(Error(reason), run))
        Ok(effect) ->
          case effect {
            harness.StandardOut(text) ->
              promise.resolve(#(
                Ok(standard_out.encode(Nil)),
                Run(..run, output: [text, ..run.output]),
              ))
            harness.StandardError(text) ->
              promise.resolve(#(
                Ok(standard_error.encode(Nil)),
                Run(..run, output: [text, ..run.output]),
              ))
            harness.StandardIn ->
              promise.resolve(#(
                Ok(standard_in.encode(Error("no standard input in opencode"))),
                run,
              ))
            harness.Cwd ->
              promise.resolve(#(Ok(cwd.encode(Ok(run.directory))), run))
            harness.Exit(_) ->
              promise.resolve(#(Error(unavailable(label, lift)), run))
            _ -> {
              use value <- promise.map(
                system.run(computer.extrinsic(effect, meta.origin)),
              )
              #(Ok(value), run)
            }
          }
      }
  }
}

fn call_host(
  handler: Dynamic,
  input: Dynamic,
  raw: execute.Value,
) -> Promise(Result(Dynamic, String)) {
  case
    foreign.try_apply(
      handler,
      array.from_list([input, foreign.to_dynamic(raw)]),
    )
  {
    Error(reason) -> promise.resolve(Error(host_error(reason)))
    Ok(value) ->
      foreign.to_promise(value)
      |> promise.map(Ok)
      |> promise.rescue(fn(reason) { Error(host_error(reason)) })
  }
}

fn host_error(reason) {
  native_string.from(reason) |> result.unwrap("host callback failed")
}

/// Relative imports read files so they are decided by the `read_file` gate.
fn lookup(reference, meta: source.Location, run: Run) {
  case reference {
    ir.Relative(path) -> {
      use resolved <- promise.await(
        system.run(source.resolve_filepath(meta.origin, path)),
      )
      case resolved {
        Error(reason) -> promise.resolve(#(Error(abort(reason)), run))
        Ok(path) -> load_relative(path, meta, run)
      }
    }
    _ -> do_lookup(reference, meta, run)
  }
}

fn abort(message) {
  break.UnhandledEffect("Abort", v.String(message))
}

fn load_relative(path, meta, run: Run) {
  let request =
    v.Record(
      dict.from_list([
        #("path", v.String(path)),
        #("offset", v.Integer(0)),
        #("limit", v.Integer(100_000_000)),
      ]),
    )
  let run = Run(..run, effects: ["ReadFile", ..run.effects])
  use #(reply, run, path) <- promise.await(read_import(path, request, meta, run))
  case reply {
    Ok(v.Tagged("Ok", v.Binary(bytes))) -> {
      case
        bit_array.to_string(bytes)
        |> result.replace_error("module is not UTF-8")
      {
        Error(reason) -> promise.resolve(#(Error(abort(reason)), run))
        Ok(code) ->
          case source.parse(code, source.Disk(path)) {
            Error(reason) -> promise.resolve(#(Error(abort(reason)), run))
            Ok(code) -> pure_import(expression.execute(code, []), run)
          }
      }
    }
    Ok(value) ->
      promise.resolve(#(
        Error(abort(
          "import of " <> path <> " refused: " <> simple_debug.inspect(value),
        )),
        run,
      ))
    Error(reason) -> promise.resolve(#(Error(reason), run))
  }
}

fn read_import(path, request, meta, run: Run) {
  case policy.access(run.policy, "ReadFile") {
    policy.Unavailable | policy.Open ->
      promise.resolve(#(Error(unavailable("ReadFile", request)), run, path))
    policy.Gated(gates) -> {
      use #(decision, run) <- promise.await(gate(
        "ReadFile",
        gates,
        request,
        meta,
        run,
      ))
      case decision {
        Ok(policy.Pass(request)) ->
          case cast.field("path", cast.as_string, request) {
            Error(reason) -> promise.resolve(#(Error(reason), run, path))
            Ok(path) -> {
              use #(reply, run) <- promise.map(perform(
                "ReadFile",
                request,
                meta,
                run,
              ))
              #(reply, run, path)
            }
          }
        Ok(policy.Mock(value)) -> promise.resolve(#(Ok(value), run, path))
        Error(reason) -> promise.resolve(#(Error(reason), run, path))
      }
    }
  }
}

// Imports can define effectful functions, but loading a module is pure. Nested
// references return here so every file read meets the same policy again.
fn pure_import(return, run: Run) {
  case return {
    Ok(value) -> promise.resolve(#(Ok(value), run))
    Error(#(break.UndefinedReference(reference), meta, env, k)) -> {
      use #(value, run) <- promise.await(lookup(reference, meta, run))
      case value {
        Ok(value) -> pure_import(expression.resume(value, env, k), run)
        Error(reason) -> promise.resolve(#(Error(reason), run))
      }
    }
    Error(#(reason, _, _, _)) -> promise.resolve(#(Error(reason), run))
  }
}

fn do_lookup(reference, meta: source.Location, run: Run) {
  use #(result, state) <- promise.map(
    system.run(execute.lookup(reference, meta.origin, run.state)),
  )
  #(result, Run(..run, state:))
}

/// Names of the agents that have a policy in the configuration.
pub fn agent_names(config: Config) -> List(String) {
  dict.keys(config.agents) |> list.sort(string.compare)
}

/// Explain an effect the policy does not allow, the interpreter only knows it was not handled.
fn denied(reason, policy, hosts: List(Host)) {
  case reason {
    break.UnhandledEffect(label, _) ->
      case available(policy, label) {
        True -> ""
        False -> {
          let known =
            list.any(computer.effects(), fn(i) { i.name == label })
            || list.any(hosts, fn(h) { h.label == label })
          case known {
            True ->
              "The effect "
              <> label
              <> " is not allowed by your policy, it has no `"
              <> policy.field(label)
              <> "` gate.\n"
            False -> "There is no effect called " <> label <> ".\n"
          }
        }
      }
    _ -> ""
  }
}
