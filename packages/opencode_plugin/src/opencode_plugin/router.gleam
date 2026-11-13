//// EYG-only and gated tool sets. A host supplies its own normal tool dispatcher.
//// Task reports a child session id before running it, preserving that policy.

import eyg/interpreter/simple_debug
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import javascript/mutable_reference as reference
import opencode_plugin as core
import opencode_plugin/convert
import opencode_plugin/policy.{type Policy}
import opencode_plugin/tools
import plinthx/javascript/foreign

pub type Mode {
  Only
  Gate
  Off
}

pub type Session {
  Session(id: String, parent: Option(String), directory: String, agent: String)
}

/// The started callback must run before the child issues any tool calls.
pub type Tool {
  Tool(
    id: String,
    description: String,
    schema: Dynamic,
    execute: fn(Dynamic, fn(String) -> Nil) -> Promise(String),
  )
}

pub opaque type Router {
  Router(
    config: core.Config,
    policies: reference.MutableReference(dict.Dict(String, Policy)),
  )
}

/// Recreate the router when trusted configuration changes.
pub fn new(config: core.Config) {
  Router(config, reference.new(dict.new()))
}

/// Trusted adapters keep policy assignments shared with later host callbacks.
pub fn known(router: Router, id: String) {
  dict.get(reference.get(router.policies), id)
}

pub fn remember(router: Router, id: String, policy: Policy) {
  let _ =
    reference.set(
      router.policies,
      dict.insert(reference.get(router.policies), id, policy),
    )
  Nil
}

pub fn policy(router: Router, session: Session, parent) {
  policy_for(router, session, parent, [])
}

fn text(value, field) {
  decode.run(value, decode.field(field, decode.string, decode.success))
  |> result.unwrap("")
}

fn fail(reason) {
  foreign.raise(foreign.error(reason))
}

fn policy_for(
  router: Router,
  session: Session,
  parent,
  seen,
) -> Promise(Policy) {
  case list.contains(seen, session.id) {
    True -> fail("cyclic session ancestry")
    False -> Nil
  }
  case dict.get(reference.get(router.policies), session.id) {
    Ok(policy) -> promise.resolve(policy)
    Error(_) -> {
      let base = case
        core.agent_policy(router.config, session.agent),
        session.parent
      {
        Ok(policy), _ -> promise.resolve(policy)
        Error(_), None -> promise.resolve(core.config_policy(router.config))
        Error(_), Some(id) -> {
          use above <- promise.await(parent(id))
          case above {
            None -> fail("missing parent session " <> id)
            Some(above) ->
              policy_for(router, above, parent, [session.id, ..seen])
          }
        }
      }
      use policy <- promise.map(base)
      let _ =
        reference.set(
          router.policies,
          dict.insert(reference.get(router.policies), session.id, policy),
        )
      policy
    }
  }
}

fn hosts(router: Router, policy, available: List(Tool)) {
  list.map(available, fn(tool) {
    core.host(
      tools.label(tool.id),
      tools.type_(tool.schema),
      "String",
      foreign.to_dynamic(fn(input, raw) {
        let input = tools.argument(input, tool.schema)
        case tool.id {
          "task" -> {
            let base =
              core.agent_policy(router.config, text(input, "subagent_type"))
              |> result.unwrap(policy)
            let child = case core.field(raw, "policy") {
              Error(_) -> base
              Ok(requested) ->
                case core.restrict(base, requested) {
                  Ok(policy) -> policy
                  Error(reason) -> fail(reason)
                }
            }
            let assert Ok(fields) =
              decode.run(input, decode.dict(decode.string, decode.dynamic))
            let input =
              fields
              |> dict.delete("policy")
              |> dict.to_list
              |> array.from_list
              |> foreign.object
            tool.execute(input, fn(id) { remember(router, id, child) })
          }
          _ -> tool.execute(input, fn(_) { Nil })
        }
      }),
    )
  })
}

pub fn run(
  router: Router,
  session: Session,
  available: List(Tool),
  parent,
  code: String,
) {
  use policy <- promise.await(policy_for(router, session, parent, []))
  core.run(
    code,
    policy,
    core.config_context(router.config),
    session.directory,
    hosts(router, policy, available),
  )
}

pub fn describe(
  router: Router,
  session: Session,
  available: List(Tool),
  parent,
) {
  use policy <- promise.map(policy_for(router, session, parent, []))
  "Run EYG with perform Label(lift). Every effect is checked by the user's policy.\n"
  <> "Tool fields use snake case; ? fields are optional. File paths are absolute when a gate sees them.\n"
  <> "Task accepts an optional policy record restricting the named agent's configured policy, or its parent's.\n"
  <> core.describe(policy, hosts(router, policy, available))
  <> "\n"
  <> core.config_readme(router.config)
}

/// A direct native call runs through exactly the same effect and policy path.
pub fn single(id: String, arguments: Dynamic) {
  let literal =
    arguments |> tools.result |> convert.from_js |> simple_debug.inspect
  "match perform "
  <> tools.label(id)
  <> "("
  <> literal
  <> ") { Ok(value) -> { value } Error(reason) -> { Error(reason) } }"
}

fn output(report: core.Report) {
  case report.ok {
    True -> core.report_text(report)
    False -> "Error\n" <> core.report_text(report)
  }
}

/// The host keeps its validation, permission, hook and event behavior inside Tool.execute.
pub fn wrap(
  router: Router,
  session: Session,
  available: List(Tool),
  parent,
  mode: Mode,
) {
  case mode {
    Off -> promise.resolve(available)
    _ -> {
      use description <- promise.map(describe(
        router,
        session,
        available,
        parent,
      ))
      let assert Ok(schema) =
        json.parse(
          "{\"type\":\"object\",\"properties\":{\"code\":{\"type\":\"string\"}},\"required\":[\"code\"]}",
          decode.dynamic,
        )
      let eyg =
        Tool("eyg", description, schema, fn(input, _) {
          run(router, session, available, parent, text(input, "code"))
          |> promise.map(output)
        })
      case mode {
        Only -> [eyg]
        Gate -> [
          eyg,
          ..list.map(available, fn(tool) {
            Tool(..tool, execute: fn(input, _) {
              run(router, session, available, parent, single(tool.id, input))
              |> promise.map(output)
            })
          })
        ]
        Off -> available
      }
    }
  }
}
