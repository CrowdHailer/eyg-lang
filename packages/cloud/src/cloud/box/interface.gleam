//// Executable interface contracts are checked before their root is published.

import clockwork
import cloud/beam/execute
import cloud/box/check
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import overlay/policy
import touch_grass/harness/computer
import touch_grass/interface

pub type Config {
  Config(handler: state.Value(execute.Meta), policy: execute.Policy)
}

pub type Cron {
  Cron(name: String, expression: String, config: Config)
}

pub fn request_type() {
  t.record([
    #("method", t.String),
    #("path", t.String),
    #("body", t.Binary),
    #("headers", t.List(t.record([#("name", t.String), #("value", t.String)]))),
  ])
}

pub fn response_type() {
  t.record([
    #("status", t.Integer),
    #("body", t.Binary),
    #("headers", t.List(t.record([#("name", t.String), #("value", t.String)]))),
  ])
}

pub fn rules() {
  policy.match_rules(computer.effects(), execute.rules)
}

pub fn decode(value) {
  let decoded = {
    use handler <- result.try(cast.field("handler", Ok, value))
    use policy <- result.try(cast.field(
      "policy",
      policy.decode_policy(rules(), _),
      value,
    ))
    Ok(Config(handler, policy))
  }
  result.map_error(decoded, simple_debug.describe)
}

pub fn validate(modules, runtime) {
  list.try_fold(dict.to_list(modules), runtime, fn(runtime, pair) {
    let #(path, module) = pair
    case path == "/system/http.eyg", is_cron(path) {
      True, _ -> contract(module, request_type(), response_type(), runtime)
      _, True -> {
        use runtime <- result.try(contract(module, t.unit, t.unit, runtime))
        use cron <- result.try(cron(path, module))
        use _ <- result.map(
          clockwork.from_string(cron.expression)
          |> result.replace_error(path <> ": invalid cron"),
        )
        runtime
      }
      _, _ -> Ok(runtime)
    }
  })
}

fn contract(module: check.Module, input, output, runtime) {
  let source = ir.clear_annotation(module.source)
  let call =
    ir.apply(ir.get(source, "handler"), ir.variable("$request"))
    |> ir.map_annotation(fn(_) { #(0, 0) })
  let context =
    infer.pure()
    |> infer.with_effects(
      interface.types(list.map(rules(), fn(rule) { rule.0 })),
    )
    |> infer.with_expected_type(output)
  let context = infer.Context(..context, env: [#("$request", input)])
  use runtime <- result.try(check.check(infer.check(context, call), runtime))
  let policy_source =
    ir.get(source, "policy") |> ir.map_annotation(fn(_) { #(0, 0) })
  let context = infer.pure() |> infer.with_expected_type(policy.type_(rules()))
  use runtime <- result.try(check.check(
    infer.check(context, policy_source),
    runtime,
  ))
  use _ <- result.map(decode(module.value))
  runtime
}

pub fn is_cron(path) {
  string.starts_with(path, "/system/cron/") && string.ends_with(path, ".eyg")
}

pub fn cron(path, module: check.Module) {
  use config <- result.try(decode(module.value))
  use expression <- result.map(
    cast.field("cron", cast.as_string, module.value)
    |> result.map_error(simple_debug.describe),
  )
  Cron(path, expression, config)
}

pub fn crons(modules) {
  dict.to_list(modules)
  |> list.filter_map(fn(pair) {
    case is_cron(pair.0) {
      True -> cron(pair.0, pair.1)
      False -> Error("Not a cron")
    }
  })
}
