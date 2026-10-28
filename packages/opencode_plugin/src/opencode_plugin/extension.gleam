//// The public OpenCode plugin interface. Its EYG tool supplies computer
//// effects and SDK-backed Task/Escalate; the full native dispatcher is separate.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import opencode_plugin as core
import opencode_plugin/configuration.{type Loaded}
import opencode_plugin/native as n
import opencode_plugin/policy.{type Policy}
import opencode_plugin/router
import opencode_plugin/sdk
import plinthx/javascript/foreign

const task_type = "{agent: String, prompt: String, policy: {..gates}}"

const description =
  "Run EYG with perform Label(lift). Every effect is checked by the user's policy; unlisted effects are unavailable. context is in scope. Each run starts fresh and returns its last value plus captured output. Paths are absolute when a gate sees them."

fn session(info, agent, directory) {
  let parent = case n.string(info, "parentID") {
    "" -> None
    id -> Some(id)
  }
  router.Session(n.string(info, "id"), parent, directory, agent)
}

fn get_session(client, id) {
  n.call(n.field(client, "session"), "get", [
    n.object([#("path", n.object([#("id", n.data(id))]))]),
  ])
  |> foreign.to_promise
  |> promise.map(fn(reply) {
    let info = n.field(reply, "data")
    case n.string(info, "id") == id {
      True -> info
      False -> n.fail("failed to read session " <> id)
    }
  })
}

fn policy(loaded: Loaded, client, id, agent, directory) -> Promise(Policy) {
  case id {
    "" -> promise.resolve(core.config_policy(loaded.config))
    _ ->
      case router.known(loaded.router, id) {
        Ok(policy) -> promise.resolve(policy)
        Error(_) -> {
          use info <- promise.await(get_session(client, id))
          let info = n.with_fields(info, [#("id", n.data(id))])
          let parent = fn(id) {
            use info <- promise.map(get_session(client, id))
            case n.string(info, "id") {
              "" -> None
              _ -> Some(session(info, "", directory))
            }
          }
          router.policy(loaded.router, session(info, agent, directory), parent)
        }
      }
  }
}

fn hosts(loaded: Loaded, current, client, ctx) {
  let start = fn(escalate) {
    n.data(fn(input: Dynamic, raw) {
      let decoded =
        decode.run(input, {
          use agent <- decode.field("agent", decode.string)
          use prompt <- decode.field("prompt", decode.string)
          decode.success(#(agent, prompt))
        })
      let #(agent, prompt) = case decoded {
        Ok(value) -> value
        Error(_) -> n.fail("Task needs string agent and prompt fields")
      }
      let requested = case core.field(raw, "policy") {
        Ok(policy) -> policy
        Error(_) -> n.fail("a subagent needs a policy field")
      }
      let child = case escalate {
        True -> core.replace(requested)
        False ->
          core.restrict(
            core.agent_policy(loaded.config, agent) |> result.unwrap(current),
            requested,
          )
      }
      let child = case child {
        Ok(policy) -> policy
        Error(reason) -> n.fail(reason)
      }
      let approval = case escalate {
        False -> promise.resolve(n.data(Nil))
        True ->
          n.call(ctx, "ask", [
            n.object([
              #("permission", n.data("eyg_escalate")),
              #("patterns", n.array([n.data(agent)])),
              #("always", n.array([])),
              #(
                "metadata",
                n.object([
                  #("agent", n.data(agent)),
                  #("prompt", n.data(prompt)),
                  #("effects", n.data(array.from_list(core.fields(child)))),
                ]),
              ),
            ]),
          ])
          |> foreign.to_promise
      }
      use _ <- promise.await(approval)
      subagent(loaded, client, n.string(ctx, "sessionID"), agent, prompt, child)
    })
  }
  [
    core.host("Task", task_type, "String", start(False)),
    core.host("Escalate", task_type, "String", start(True)),
  ]
}

fn subagent(loaded: Loaded, client, parent, agent, prompt, policy) {
  use created <- promise.await(
    n.call(n.field(client, "session"), "create", [
      n.object([
        #(
          "body",
          n.object([
            #("parentID", n.data(parent)),
            #(
              "title",
              n.data(agent <> " (eyg): " <> string.slice(prompt, 0, 60)),
            ),
          ]),
        ),
      ]),
    ])
    |> foreign.to_promise,
  )
  let id = n.string(n.field(created, "data"), "id")
  case id {
    "" -> n.fail("failed to create a subagent session")
    _ -> Nil
  }
  router.remember(loaded.router, id, policy)
  let message = n.object([#("type", n.data("text")), #("text", n.data(prompt))])
  let body =
    n.object([#("agent", n.data(agent)), #("parts", n.array([message]))])
  use reply <- promise.map(
    n.call(n.field(client, "session"), "prompt", [
      n.object([
        #("path", n.object([#("id", n.data(id))])),
        #("body", body),
      ]),
    ])
    |> foreign.to_promise,
  )
  case foreign.is_undefined(n.field(reply, "error")) {
    False -> n.fail("subagent request failed")
    True -> {
      n.list(n.field(n.field(reply, "data"), "parts"))
      |> list.filter(fn(part) { n.string(part, "type") == "text" })
      |> list.last
      |> result.map(n.string(_, "text"))
      |> result.unwrap("")
    }
  }
}

/// Native entry binds embedded resource data to this Gleam factory.
pub fn create(resources: Dynamic) {
  let load = configuration.loader(n.string(resources, "plugin"))
  fn(input: Dynamic) {
    let directory = n.string(input, "directory")
    let client = n.field(input, "client")
    let get_policy = fn(ctx) {
      use loaded <- promise.await(load(directory))
      use policy <- promise.map(policy(
        loaded,
        client,
        n.string(ctx, "sessionID"),
        n.string(ctx, "agent"),
        directory,
      ))
      #(loaded, policy)
    }
    let execute =
      n.data(fn(args, ctx) {
        use #(loaded, policy) <- promise.await(get_policy(ctx))
        use report <- promise.map(core.run(
          n.string(args, "code"),
          policy,
          core.config_context(loaded.config),
          directory,
          hosts(loaded, policy, client, ctx),
        ))
        let effects = list.unique(report.effects)
        n.object([
          #(
            "title",
            n.data(case effects {
              [] -> "pure"
              _ -> string.join(effects, ", ")
            }),
          ),
          #(
            "output",
            n.data(case report.ok {
              True -> core.report_text(report)
              False -> "Error\n" <> core.report_text(report)
            }),
          ),
          #(
            "metadata",
            n.object([
              #("ok", n.data(report.ok)),
              #("effects", n.data(array.from_list(effects))),
            ]),
          ),
        ])
      })
    promise.resolve(
      n.object([
        #(
          "tool",
          n.object([
            #(
              "eyg",
              n.object([
                #("description", n.data(description)),
                #(
                  "args",
                  n.object([
                    #(
                      "code",
                      n.call(sdk.string_schema(), "describe", [
                        n.data("EYG source code to run"),
                      ]),
                    ),
                  ]),
                ),
                #("execute", execute),
              ]),
            ),
          ]),
        ),
        #(
          "chat.message",
          n.data(fn(message, _output) {
            get_policy(message) |> promise.map(fn(_) { Nil })
          }),
        ),
        #(
          "experimental.chat.system.transform",
          n.data(fn(request, output) {
            use #(loaded, policy) <- promise.map(get_policy(request))
            let effects =
              core.describe(policy, hosts(loaded, policy, client, request))
            let prompt =
              "# EYG\n"
              <> description
              <> "\nA gate returns Pass(lift) or Mock(reply).\nEffects available:\n"
              <> effects
              <> "\nTask starts a restricted child session. A named agent's configured policy is its starting policy; otherwise yours is restricted. Escalate replaces it after host permission approval.\n"
              <> "Agents with configured policies: "
              <> string.join(core.agent_names(loaded.config), ", ")
              <> "\nContext:\n"
              <> core.config_readme(loaded.config)
              <> "\n\n"
              <> n.string(resources, "syntax")
              <> "\n\n"
              <> n.string(resources, "builtins")
            let _ = n.call(n.field(output, "system"), "push", [n.data(prompt)])
            Nil
          }),
        ),
      ]),
    )
  }
}
