//// A pi extension: the model runs EYG, host tools become policy-gated effects.

import envoy
import filepath
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri
import javascript/mutable_reference as reference
import opencode_plugin as core
import opencode_plugin/tools
import pi_extension/native as n
import pi_extension/sdk
import plinthx/javascript/foreign
import plinthx/javascript/module
import simplifile

const instructions =
  "Run an EYG program with perform Label(lift). Every effect is checked by the user's policy; unlisted effects are unavailable. Host tool fields use snake case, ? fields are optional. context is in scope. Each run starts fresh. Paths are absolute when a gate sees them. A gate returns Pass(lift) to call the host or Mock(reply) to resume without it."

const task_lift = "{agent: String, prompt: String, policy: {..gates}}"

type Loaded {
  Loaded(key: String, config: core.Config)
}

fn resource(name, fallback) {
  let assert Ok(url) = uri.parse(module.url())
  let path = uri.percent_decode(url.path) |> result.unwrap(url.path)
  case simplifile.read(filepath.join(filepath.directory_name(path), name)) {
    Ok(text) -> text
    Error(_) -> {
      let assert Ok(text) = simplifile.read(fallback)
      text
    }
  }
}

fn parameters() {
  sdk.object_schema(
    n.object([
      #(
        "code",
        sdk.string_schema(
          n.object([#("description", n.data("EYG source code to run"))]),
        ),
      ),
    ]),
  )
}

fn config(current, loaded, default_policy) {
  let cwd = reference.get(current)
  let home = envoy.get("HOME") |> result.unwrap("")
  let agent_dir =
    envoy.get("PI_CODING_AGENT_DIR")
    |> result.unwrap(filepath.join(home, ".pi/agent"))
  let candidates = [
    envoy.get("PI_EYG_CONFIG") |> result.unwrap(""),
    filepath.join(cwd, ".pi/eyg.eyg"),
    filepath.join(agent_dir, "eyg.eyg"),
  ]
  let #(path, code) = case
    list.find(candidates, fn(path) {
      path != "" && simplifile.is_file(path) == Ok(True)
    })
  {
    Ok(path) -> {
      let assert Ok(code) = simplifile.read(path)
      #(path, code)
    }
    Error(_) -> #(
      filepath.join(cwd, "eyg"),
      string.replace(default_policy, "\"PROJECT\"", string.inspect(cwd)),
    )
  }
  let key = path <> "\n" <> code
  case reference.get(loaded) {
    Some(Loaded(known, config)) if known == key -> promise.resolve(config)
    _ -> {
      use configured <- promise.map(core.load_source(code, path))
      case configured {
        Error(reason) ->
          n.fail("Failed to load EYG configuration " <> path <> "\n" <> reason)
        Ok(config) -> {
          reference.set(loaded, Some(Loaded(key, config)))
          config
        }
      }
    }
  }
}

fn only(pi) {
  n.call(pi, "getFlag", [n.data("eyg-only")]) == n.data(True)
  || envoy.get("PI_EYG_ONLY") == Ok("1")
}

pub fn main(pi: Dynamic) {
  let assert Ok(cwd) = simplifile.current_directory()
  let current = reference.new(cwd)
  let loaded = reference.new(None)
  let syntax = resource("syntax.md", "../../guides/syntax.md")
  let default_policy =
    resource("default.eyg", "../opencode_plugin/plugin/default.eyg")
  let get_config = fn() { config(current, loaded, default_policy) }
  let _ =
    n.call(pi, "registerFlag", [
      n.data("eyg-only"),
      n.object([
        #("type", n.data("boolean")),
        #("default", n.data(False)),
        #(
          "description",
          n.data(
            "Give the model only EYG; other tools remain callable as effects",
          ),
        ),
      ]),
    ])
  let _ =
    n.call(pi, "on", [
      n.data("session_start"),
      n.data(fn(_event, ctx) {
        reference.set(current, n.string(ctx, "cwd"))
        get_config() |> promise.map(fn(_) { Nil })
      }),
    ])
  let _ =
    n.call(pi, "registerTool", [
      n.object([
        #("name", n.data("eyg")),
        #("label", n.data("EYG")),
        #("description", n.data(instructions)),
        #("promptSnippet", n.data("Run EYG under the user's policy")),
        #("parameters", parameters()),
        #("executionMode", n.data("sequential")),
        #(
          "prepareLoadout",
          n.data(fn(loadout) {
            case reference.get(loaded) {
              None -> n.data(Nil)
              Some(Loaded(_, config)) -> {
                let callable = n.list(n.field(loadout, "callable"))
                let description =
                  describe(core.config_policy(config), callable, config, syntax)
                let hidden = case only(pi) {
                  True ->
                    n.list(n.field(loadout, "declared"))
                    |> list.map(n.string(_, "name"))
                    |> list.filter(fn(name) { name != "eyg" })
                  False -> []
                }
                n.object([
                  #("descriptions", n.object([#("eyg", n.data(description))])),
                  #(
                    "hiddenDeclarations",
                    foreign.to_dynamic(gleam_array(hidden)),
                  ),
                ])
              }
            }
          }),
        ),
        #(
          "execute",
          n.data(fn(_id, params, signal, _update, ctx) {
            let _ = reference.set(current, n.string(ctx, "cwd"))
            use config <- promise.await(get_config())
            let spent = reference.new(None)
            use report <- promise.map(execute(
              n.string(params, "code"),
              core.config_policy(config),
              ctx,
              config,
              syntax,
              spent,
              signal,
            ))
            case report.ok {
              False -> n.fail(core.report_text(report))
              True -> {
                let fields = [
                  #(
                    "content",
                    n.array([
                      n.object([
                        #("type", n.data("text")),
                        #("text", n.data(core.report_text(report))),
                      ]),
                    ]),
                  ),
                  #(
                    "details",
                    n.object([
                      #(
                        "effects",
                        n.data(gleam_array(list.unique(report.effects))),
                      ),
                    ]),
                  ),
                ]
                let fields = case reference.get(spent) {
                  None -> fields
                  Some(usage) -> [#("usage", usage), ..fields]
                }
                n.object(fields)
              }
            }
          }),
        ),
      ]),
    ])
  // Retain a valid configuration for the first prepareLoadout. Bad config is
  // retried by execute/session_start, which fail closed with its actual error.
  get_config() |> promise.map(fn(_) { Nil }) |> promise.rescue(fn(_) { Nil })
}

fn gleam_array(values) {
  // Kept typed so native SDK arrays never receive a Gleam linked list.
  values |> list.map(n.data) |> n.array
}

fn tool_hosts(callable, run) {
  callable
  |> list.filter(fn(tool) { n.string(tool, "name") != "eyg" })
  |> list.map(fn(tool) {
    let name = n.string(tool, "name")
    let schema = n.field(tool, "parameters")
    core.host(
      tools.label(name),
      tools.type_(schema),
      "Any",
      n.data(fn(input, _raw) { run(name, tools.argument(input, schema)) }),
    )
  })
}

fn placeholders() {
  [
    core.host("Task", task_lift, "String", n.data(Nil)),
    core.host("Escalate", task_lift, "String", n.data(Nil)),
  ]
}

fn describe(policy, callable, config, syntax) {
  let effects =
    core.describe(
      policy,
      list.append(
        tool_hosts(callable, fn(_, _) { n.data(Nil) }),
        placeholders(),
      ),
    )
  instructions
  <> "\n\nEffects available:\n"
  <> effects
  <> "\nTask starts a subagent with only EYG. Its policy is the named agent's configured policy, or yours, restricted by the policy record you pass. Escalate replaces the policy after explicit UI approval.\n"
  <> "Agents with configured policies: "
  <> string.join(core.agent_names(config), ", ")
  <> "\n"
  <> core.config_readme(config)
  <> "\n\n"
  <> syntax
}

fn execute(
  code,
  policy,
  ctx,
  config,
  syntax,
  spent,
  signal,
) -> promise.Promise(core.Report) {
  let hosts =
    tool_hosts(n.list(n.field(ctx, "tools")), fn(name, input) {
      use outcome <- promise.map(
        n.call(ctx, "executeTool", [
          n.data(name),
          input,
          n.object([#("signal", signal)]),
        ])
        |> foreign.to_promise,
      )
      let result = n.field(outcome, "result")
      let text = n.tool_text(n.field(result, "content"))
      case n.bool(n.field(outcome, "isError")) {
        True -> n.fail(text)
        False ->
          case foreign.is_undefined(n.field(result, "structuredContent")) {
            True -> n.data(text)
            False -> tools.result(n.field(result, "structuredContent"))
          }
      }
    })
  let start = fn(escalate) {
    n.data(fn(input, raw) {
      let child = case core.field(raw, "policy") {
        Error(_) -> n.fail("a subagent needs a policy field")
        Ok(requested) ->
          case escalate {
            True -> core.replace(requested)
            False ->
              core.restrict(
                core.agent_policy(config, n.string(input, "agent"))
                  |> result.unwrap(policy),
                requested,
              )
          }
      }
      let child = case child {
        Ok(child) -> child
        Error(reason) -> n.fail(reason)
      }
      use approved <- promise.await(case escalate {
        False -> promise.resolve(True)
        True ->
          case n.bool(n.field(ctx, "hasUI")) {
            False -> promise.resolve(False)
            True ->
              n.call(n.field(ctx, "ui"), "confirm", [
                n.data("Escalate to a subagent?"),
                n.data(
                  n.string(input, "agent")
                  <> "\nEffects: "
                  <> string.join(core.fields(child), ", ")
                  <> "\n\n"
                  <> n.string(input, "prompt"),
                ),
              ])
              |> foreign.to_promise
              |> promise.map(n.bool)
          }
      })
      case approved {
        False -> n.fail("the user did not approve the escalation")
        True -> subagent(input, child, ctx, config, syntax, spent, signal)
      }
    })
  }
  let hosts =
    list.append(hosts, [
      core.host("Task", task_lift, "String", start(False)),
      core.host("Escalate", task_lift, "String", start(True)),
    ])
  core.run(
    code,
    policy,
    core.config_context(config),
    n.string(ctx, "cwd"),
    hosts,
  )
}

fn subagent(
  input,
  policy,
  ctx,
  config,
  syntax,
  spent,
  signal,
) -> promise.Promise(String) {
  let model = n.field(ctx, "model")
  case foreign.is_undefined(model) {
    True -> n.fail("no model selected")
    False -> Nil
  }
  let tool =
    n.object([
      #("name", n.data("eyg")),
      #("label", n.data("EYG")),
      #(
        "description",
        n.data(describe(policy, n.list(n.field(ctx, "tools")), config, syntax)),
      ),
      #("parameters", parameters()),
      #(
        "execute",
        n.data(fn(_id, params, child_signal, _update) {
          let signal = case foreign.is_undefined(child_signal) {
            True -> signal
            False -> child_signal
          }
          use report <- promise.map(execute(
            n.string(params, "code"),
            policy,
            ctx,
            config,
            syntax,
            spent,
            signal,
          ))
          case report.ok {
            False -> n.fail(core.report_text(report))
            True ->
              n.object([
                #(
                  "content",
                  n.array([
                    n.object([
                      #("type", n.data("text")),
                      #("text", n.data(core.report_text(report))),
                    ]),
                  ]),
                ),
              ])
          }
        }),
      ),
    ])
  let registry = n.field(ctx, "modelRegistry")
  let agent =
    sdk.agent(
      n.object([
        #(
          "initialState",
          n.object([
            #(
              "systemPrompt",
              n.data(
                "You are the "
                <> n.string(input, "agent")
                <> " subagent. Use EYG and answer with the result only.",
              ),
            ),
            #("model", model),
            #("tools", n.array([tool])),
          ]),
        ),
        #(
          "streamFn",
          n.data(fn(model, context, options) {
            n.call(registry, "streamSimple", [model, context, options])
          }),
        ),
      ]),
    )
  let abort =
    n.data(fn() {
      let _ = n.call(agent, "abort", [])
      Nil
    })
  let has_signal = !foreign.is_undefined(signal)
  case has_signal {
    True -> {
      case n.bool(n.field(signal, "aborted")) {
        True -> n.fail("subagent aborted")
        False -> Nil
      }
      let _ =
        n.call(signal, "addEventListener", [
          n.data("abort"),
          abort,
          n.object([#("once", n.data(True))]),
        ])
      Nil
    }
    False -> Nil
  }
  let outcome =
    n.call(agent, "prompt", [n.data(n.string(input, "prompt"))])
    |> foreign.to_promise
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.map(outcome)
  case has_signal {
    True -> {
      let _ = n.call(signal, "removeEventListener", [n.data("abort"), abort])
      Nil
    }
    False -> Nil
  }
  case outcome {
    Error(reason) -> foreign.raise(reason)
    Ok(_) -> Nil
  }
  let messages =
    n.list(n.field(n.field(agent, "state"), "messages"))
    |> list.filter(fn(message) { n.string(message, "role") == "assistant" })
  list.each(messages, fn(message) {
    let usage = n.field(message, "usage")
    case foreign.is_undefined(usage) {
      True -> Nil
      False -> {
        let _ =
          reference.set(spent, Some(add_usage(reference.get(spent), usage)))
        Nil
      }
    }
  })
  case list.first(list.reverse(messages)) {
    Error(_) -> ""
    Ok(last) ->
      case n.string(last, "stopReason") {
        "error" -> n.fail(n.string(last, "errorMessage"))
        _ -> n.joined_text(n.field(last, "content"))
      }
  }
}

fn number(value, field) {
  decode.run(n.field(value, field), decode.float) |> result.unwrap(0.0)
}

pub fn add_usage(previous, next) {
  case previous {
    None -> next
    Some(previous) -> {
      let totals =
        list.map(
          ["input", "output", "cacheRead", "cacheWrite", "totalTokens"],
          fn(key) { #(key, n.data(number(previous, key) +. number(next, key))) },
        )
      let costs =
        list.map(
          ["input", "output", "cacheRead", "cacheWrite", "total"],
          fn(key) {
            #(
              key,
              n.data(
                number(n.field(previous, "cost"), key)
                +. number(n.field(next, "cost"), key),
              ),
            )
          },
        )
      n.object([#("cost", n.object(costs)), ..totals])
    }
  }
}
