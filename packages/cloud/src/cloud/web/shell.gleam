//// The web shell, a Lustre server component served over a howdy WebSocket.
////
//// It starts unbound, running programs with the person's shell policy.
//// `perform Bind({workspace, channel})` runs the following programs as that channel,
//// with its shell policy and host, the point of view of the channel's agent.

import cloud/beam/execute
import cloud/registry
import cloud/users.{type User}
import cloud/web/runner.{type Binding, type Context}
import eyg/interpreter/simple_debug
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/keyed
import lustre/event
import lustre/server_component

pub type Args {
  Args(
    context: Context,
    user: User,
    shells: List(String),
    /// Code to start the textarea with, from `/shell?code=...`.
    code: String,
    /// A channel to bind to when the shell starts, from `/shell?workspace=...&channel=...`.
    bind: Option(Binding),
  )
}

pub type Cell {
  Cell(
    code: String,
    at: String,
    output: List(String),
    result: Result(String, String),
  )
}

pub type Model {
  Model(
    args: Args,
    user: User,
    binding: Option(Binding),
    cells: List(Cell),
    input: String,
    running: Bool,
    /// Counts runs, the textarea is replaced after each run to empty it.
    runs: Int,
  )
}

pub type Msg {
  Typed(String)
  /// Run the code, from the textarea when Ctrl+Enter is pressed or the latest typed by the Run button.
  Run(code: String)
  Ran(Cell, Option(Binding))
  Unbind
  ChooseShell(String)
}

pub fn app() -> lustre.App(Args, Model, Msg) {
  lustre.application(init, update, view)
}

fn init(args: Args) -> #(Model, Effect(Msg)) {
  let start = case args.bind {
    Some(runner.Binding(workspace:, channel:)) ->
      run(
        args,
        args.user,
        None,
        "perform Bind({workspace: \""
          <> workspace
          <> "\", channel: \""
          <> channel
          <> "\"})",
      )
    None -> effect.none()
  }
  #(
    Model(
      args:,
      user: args.user,
      binding: None,
      cells: [],
      input: "",
      running: False,
      runs: 0,
    ),
    start,
  )
}

/// Run code in a new process and report the cell and the binding after it.
fn run(args: Args, user: User, binding: Option(Binding), code: String) {
  effect.from(fn(dispatch) {
    process.spawn(fn() {
      let #(execute.Run(result:, output:), next) =
        runner.run(args.context, user, binding, code, [])
      let output = list.reverse(output) |> list.map(execute.output_text)
      let result = case result {
        Ok(value) ->
          Ok(option.map(value, simple_debug.inspect) |> option.unwrap(""))
        Error(reason) -> Error(reason)
      }
      dispatch(Ran(Cell(code, at(binding, user), output, result), next))
    })
    Nil
  })
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Typed(input) -> #(Model(..model, input:), effect.none())
    Run(code) ->
      case string.trim(code), model.running {
        "", _ | _, True -> #(model, effect.none())
        code, False -> {
          let Model(args:, user:, binding:, ..) = model
          let run = run(args, user, binding, code)
          #(Model(..model, input: "", running: True, runs: model.runs + 1), run)
        }
      }
    Ran(cell, binding) -> #(
      Model(..model, cells: [cell, ..model.cells], binding:, running: False),
      effect.none(),
    )
    Unbind -> #(Model(..model, binding: None), effect.none())
    ChooseShell(shell) -> {
      let registry = model.args.context.registry
      let user = case
        process.call(registry, 5000, registry.SetUserShell(
          model.user.name,
          shell,
          _,
        ))
      {
        Ok(Nil) -> users.User(..model.user, shell:)
        Error(_) -> model.user
      }
      #(Model(..model, user:), effect.none())
    }
  }
}

/// The code the Run button runs, the starting code until something is typed.
fn current(model: Model) -> String {
  case model.input, model.runs {
    "", 0 -> model.args.code
    input, _ -> input
  }
}

fn at(binding: Option(Binding), user: User) -> String {
  case binding {
    Some(runner.Binding(workspace:, channel:)) -> workspace <> " #" <> channel
    None ->
      case user.admin {
        True -> "admin"
        False -> user.shell
      }
  }
}

fn view(model: Model) -> Element(Msg) {
  h.div([a.class("shell")], [
    h.style([], css),
    header(model),
    h.div([a.class("cells")], list.reverse(model.cells) |> list.map(cell)),
    prompt(model),
  ])
}

fn header(model: Model) -> Element(Msg) {
  let Model(user:, binding:, ..) = model
  let who = case user.admin {
    True -> [h.span([a.class("badge admin")], [h.text("admin shell")])]
    False -> [
      h.label([], [h.text("Shell ")]),
      h.select(
        [
          a.name("shell"),
          event.on("change", {
            use value <- decode.subfield(["target", "value"], decode.string)
            decode.success(ChooseShell(value))
          })
            |> server_component.include(["target.value"]),
        ],
        list.map(model.args.shells, fn(name) {
          h.option([a.value(name), a.selected(name == user.shell)], name)
        }),
      ),
    ]
  }
  let place = case binding {
    None -> [
      h.span([a.class("badge")], [h.text("unbound")]),
      h.span([a.class("hint")], [
        h.text("perform Bind({workspace, channel}) to run as a channel"),
      ]),
    ]
    Some(runner.Binding(workspace:, channel:)) -> [
      h.span([a.class("badge bound")], [
        h.text("bound to " <> workspace <> " #" <> channel),
      ]),
      h.button([event.on_click(Unbind)], [h.text("Unbind")]),
    ]
  }
  h.div([a.class("header")], [
    h.strong([], [h.text(user.name)]),
    ..list.append(who, place)
  ])
}

fn cell(cell: Cell) -> Element(Msg) {
  let Cell(code:, at:, output:, result:) = cell
  let result = case result {
    Ok(text) -> h.pre([a.class("result")], [h.text(text)])
    Error(reason) -> h.pre([a.class("error")], [h.text(reason)])
  }
  h.div([a.class("cell")], [
    h.div([a.class("at")], [h.text(at)]),
    h.pre([a.class("code")], [h.text(code)]),
    ..case output {
      [] -> [result]
      lines -> [
        h.pre([a.class("output")], [h.text(string.concat(lines))]),
        result,
      ]
    }
  ])
}

fn prompt(model: Model) -> Element(Msg) {
  // The textarea is not controlled, so typing is never overwritten by a late update.
  // It is keyed by the number of runs, so a new empty one replaces it after each run.
  let textarea =
    h.textarea(
      [
        a.name("code"),
        a.placeholder("EYG, Ctrl+Enter to run"),
        a.attribute("spellcheck", "false"),
        a.value(case model.runs {
          0 -> model.args.code
          _ -> ""
        }),
        event.on("input", {
          use value <- decode.subfield(["target", "value"], decode.string)
          decode.success(Typed(value))
        })
          |> server_component.include(["target.value"]),
        event.on("keydown", {
          use key <- decode.field("key", decode.string)
          use ctrl <- decode.field("ctrlKey", decode.bool)
          use meta <- decode.field("metaKey", decode.bool)
          use code <- decode.subfield(["target", "value"], decode.string)
          case key, ctrl || meta {
            "Enter", True -> decode.success(Run(code))
            _, _ -> decode.failure(Run(code), "not a run shortcut")
          }
        })
          |> server_component.include([
            "key", "ctrlKey", "metaKey", "target.value",
          ]),
      ],
      case model.runs {
        0 -> model.args.code
        _ -> ""
      },
    )
  h.div([a.class("prompt")], [
    keyed.div([a.class("editor")], [#(int.to_string(model.runs), textarea)]),
    h.button([a.disabled(model.running), event.on_click(Run(current(model)))], [
      h.text(case model.running {
        True -> "Running…"
        False -> "Run"
      }),
    ]),
  ])
}

const css =
  "
.shell { font: 14px/1.45 -apple-system, sans-serif; color: #cdd6f4; background: #1e1e2e; min-height: 100vh; display: flex; flex-direction: column; }
.header { display: flex; gap: 12px; align-items: center; padding: 12px 20px; background: #181825; border-bottom: 1px solid #313244; flex-wrap: wrap; }
.badge { background: #313244; border-radius: 6px; padding: 2px 8px; font-size: 13px; }
.badge.admin { background: #f38ba8; color: #11111b; }
.badge.bound { background: #a6e3a1; color: #11111b; }
.hint { color: #7f849c; font-size: 13px; }
.cells { flex: 1; padding: 12px 20px; display: flex; flex-direction: column; gap: 12px; }
.cell { background: #181825; border-radius: 8px; padding: 10px 14px; }
.at { color: #89b4fa; font-size: 12px; }
pre { margin: 6px 0 0; font: 13px/1.45 ui-monospace, Menlo, monospace; white-space: pre-wrap; word-break: break-word; }
.code { color: #f9e2af; }
.output { color: #bac2de; }
.error { color: #f38ba8; }
.editor { flex: 1; display: flex; }
.prompt { display: flex; gap: 10px; padding: 12px 20px; background: #181825; border-top: 1px solid #313244; position: sticky; bottom: 0; }
textarea { width: 100%; box-sizing: border-box; min-height: 90px; background: #11111b; color: #cdd6f4; border: 1px solid #45475a; border-radius: 8px; padding: 10px; font: 13px/1.45 ui-monospace, Menlo, monospace; }
button { background: #89b4fa; color: #11111b; border: 0; border-radius: 8px; padding: 8px 16px; font-weight: 600; cursor: pointer; align-self: flex-end; }
select { background: #313244; color: #cdd6f4; border: 1px solid #45475a; border-radius: 6px; padding: 2px 6px; }
"
