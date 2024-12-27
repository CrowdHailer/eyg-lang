import eyg/sync/browser
import eyg/sync/sync
import eygir/expression
import gleam/javascript/promisex
import gleam/list
import gleam/option.{type Option, None, Some}
import harness/impl/browser as harness
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import morph/editable
import morph/lustre/components/key
import morph/lustre/render
import mysig/asset
import mysig/html
import website/components
import website/components/output
import website/components/snippet
import website/routes/common

pub fn app(module, func) {
  use script <- asset.do(asset.bundle(module, func))
  layout([html.empty_lustre(), h.script([a.src(asset.src(script))], "")])
}

fn layout(body) {
  use layout <- asset.do(asset.load("src/website/routes/layout.css"))
  use neo <- asset.do(asset.load("src/website/routes/neo.css"))
  html.doc(
    list.flatten([
      [
        html.stylesheet(html.tailwind_2_2_11),
        html.stylesheet(asset.src(layout)),
        html.stylesheet(asset.src(neo)),
        html.plausible("eyg.run"),
      ],
      common.page_meta(
        "/",
        "EYG",
        "EYG is a programming language for predictable, useful and most of all confident development.",
      ),
    ]),
    body,
  )
  |> asset.done()
}

pub fn page() {
  use content <- asset.do(app("website/routes/editor", "client"))
  asset.done(content)
}

pub fn client() {
  let app = lustre.application(init, update, render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub type ShellEntry {
  Executed(
    Option(snippet.Value),
    List(#(String, #(snippet.Value, snippet.Value))),
    editable.Expression,
  )
  Reloaded
}

pub type Shell {
  Shell(
    // config: spotless.Config,
    // situation: Situation,
    // cache: sync.Sync,
    previous: List(ShellEntry),
    // display_help: Bool,
    scope: snippet.Scope,
    source: snippet.Snippet,
  )
}

pub type State {
  State(
    cache: sync.Sync,
    source: snippet.Snippet,
    shell: Shell,
    display_help: Bool,
  )
}

pub fn init(_) {
  let cache = sync.init(browser.get_origin())
  let source = editable.from_expression(expression.Vacant(""))
  let snippet = snippet.init(source, [], [], cache)
  let references = snippet.references(snippet)
  let #(cache, tasks) = sync.fetch_missing(cache, references)
  let shell =
    Shell([], [], {
      let source = editable.from_expression(expression.Vacant(""))
      // TODO update hardness to spotless
      snippet.init(source, [], harness.effects(), cache)
    })
  let state = State(cache, snippet, shell, False)
  #(state, effect.from(browser.do_sync(tasks, SyncMessage)))
}

pub type Message {
  SnippetMessage(snippet.Message)
  ShellMessage(snippet.Message)
  SyncMessage(sync.Message)
}

fn dispatch_to_snippet(promise) {
  effect.from(fn(d) {
    promisex.aside(promise, fn(message) { d(SnippetMessage(message)) })
  })
}

fn dispatch_to_shell(promise) {
  effect.from(fn(d) {
    promisex.aside(promise, fn(message) { d(ShellMessage(message)) })
  })
}

fn dispatch_nothing(_promise) {
  effect.none()
}

pub fn update(state: State, message) {
  case message {
    SnippetMessage(message) -> {
      let #(snippet, eff) = snippet.update(state.source, message)
      let State(display_help: display_help, ..) = state
      let #(display_help, snippet_effect) = case eff {
        snippet.Nothing -> #(display_help, effect.none())
        snippet.AwaitRunningEffect(p) -> #(
          display_help,
          dispatch_to_snippet(snippet.await_running_effect(p)),
        )
        snippet.FocusOnCode -> #(
          display_help,
          dispatch_nothing(snippet.focus_on_buffer()),
        )
        snippet.FocusOnInput -> #(
          display_help,
          dispatch_nothing(snippet.focus_on_input()),
        )
        snippet.ToggleHelp -> #(!display_help, effect.none())
        snippet.MoveAbove -> #(display_help, effect.none())
        snippet.MoveBelow -> #(display_help, effect.none())
        snippet.ReadFromClipboard -> #(
          display_help,
          dispatch_to_snippet(snippet.read_from_clipboard()),
        )
        snippet.WriteToClipboard(text) -> #(
          display_help,
          dispatch_to_snippet(snippet.write_to_clipboard(text)),
        )
        snippet.Conclude(_, _, _) -> #(display_help, effect.none())
      }
      let #(cache, tasks) = sync.fetch_all_missing(state.cache)
      let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      let state =
        State(
          ..state,
          source: snippet,
          cache: cache,
          display_help: display_help,
        )
      #(state, effect.batch([snippet_effect, sync_effect]))
    }
    ShellMessage(message) -> {
      let shell = state.shell
      let #(source, eff) = snippet.update(shell.source, message)
      let #(shell, snippet_effect) = case eff {
        snippet.Nothing -> #(Shell(..shell, source: source), effect.none())
        snippet.AwaitRunningEffect(p) -> #(
          Shell(..shell, source: source),
          dispatch_to_shell(snippet.await_running_effect(p)),
        )
        snippet.FocusOnCode -> #(
          Shell(..shell, source: source),
          dispatch_nothing(snippet.focus_on_buffer()),
        )
        snippet.FocusOnInput -> #(
          Shell(..shell, source: source),
          dispatch_nothing(snippet.focus_on_input()),
        )
        snippet.ToggleHelp -> #(Shell(..shell, source: source), effect.none())
        snippet.MoveAbove -> {
          case shell.previous {
            [] -> todo
            [Executed(_value, effects, exp), ..] -> {
              let current =
                snippet.active(
                  exp,
                  shell.scope,
                  [],
                  // effects(state.config),
                  state.cache,
                )
              #(Shell(..shell, source: current), effect.none())
            }
            [Reloaded, Executed(_value, effects, exp), ..] -> {
              let current =
                snippet.active(
                  exp,
                  shell.scope,
                  [],
                  // effects(state.config),
                  state.cache,
                )
              #(Shell(..shell, source: current), effect.none())
            }
            _ -> todo
          }
        }
        snippet.MoveBelow -> #(Shell(..shell, source: source), effect.none())
        snippet.ReadFromClipboard -> #(
          Shell(..shell, source: source),
          dispatch_to_shell(snippet.read_from_clipboard()),
        )
        snippet.WriteToClipboard(text) -> #(
          Shell(..shell, source: source),
          dispatch_to_shell(snippet.write_to_clipboard(text)),
        )
        snippet.Conclude(value, effects, scope) -> {
          let previous = [
            Executed(value, effects, snippet.source(shell.source)),
            ..shell.previous
          ]
          // TODO eff
          let source =
            snippet.active(editable.Vacant(""), scope, [], state.cache)
          let shell = Shell(..shell, source: source, previous: previous)
          #(shell, effect.none())
        }
      }
      let #(cache, tasks) = sync.fetch_all_missing(state.cache)
      let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      let state = State(..state, shell: shell, cache: cache)
      #(state, effect.batch([snippet_effect, sync_effect]))
    }

    SyncMessage(message) -> {
      let cache = sync.task_finish(state.cache, message)
      let #(cache, tasks) = sync.fetch_all_missing(cache)
      let snippet = snippet.set_references(state.source, cache)
      #(
        State(..state, source: snippet, cache: cache),
        effect.from(browser.do_sync(tasks, SyncMessage)),
      )
    }
  }
}

pub fn render(state: State) {
  h.div([a.class("flex flex-col h-screen")], [
    components.header(fn(_) { todo as "wire auth" }, None),
    h.div([a.class("grid grid-cols-2 h-full")], [
      h.div(
        [a.class("flex-grow flex flex-col justify-center w-full  font-mono ")],
        snippet.bare_render(state.source),
      )
        |> element.map(SnippetMessage),
      h.div([a.class("cover vstack w-full bg-white")], [
        h.div([a.class("expand vstack"), a.style([#("min-height", "0")])], case
          list.length(state.shell.previous)
        {
          0 -> [
            h.h2([a.class("texl-lg font-bold")], [element.text("The console")]),
            h.div([a.class("text-gray-700")], [
              element.text("Run and test your code here. "),
              h.a([a.class("border-b border-indigo-700")], [
                element.text("help."),
              ]),
            ]),
          ]
          _ -> []
        }),
        h.div(
          [a.class("cover font-mono bg-gray-100")],
          list.map(list.reverse(state.shell.previous), fn(p) {
            case p {
              Executed(value, effects, prog) ->
                h.div([a.class("w-full max-w-4xl")], [
                  h.div(
                    [a.class("px-2 whitespace-nowrap overflow-auto")],
                    render.statements(prog),
                  ),
                  h.div(
                    [a.class("px-2 bg-gray-200")],
                    list.map(effects, fn(eff) {
                      h.div([], [
                        element.text(eff.0),
                        output.render(eff.1.0),
                        output.render(eff.1.1),
                      ])
                    }),
                  ),
                  case value {
                    Some(value) ->
                      h.div(
                        [a.class("px-2 bg-gray-200 max-h-60 overflow-auto")],
                        [output.render(value)],
                      )
                    None -> element.none()
                  },
                ])
              Reloaded ->
                h.div(
                  [
                    a.class(
                      "separator mx-12 mt-1 border-blue-400 text-blue-400",
                    ),
                  ],
                  [element.text("Reloaded")],
                )
            }
          }),
        ),
        h.div(
          [a.class("cover font-mono")],
          snippet.bare_render(state.shell.source),
        )
          |> element.map(ShellMessage),
      ]),
    ]),
    case state.display_help {
      True ->
        h.div(
          [
            a.class(
              "bottom-0 fixed flex flex-col justify-around mr-10 right-0 top-0",
            ),
          ],
          [h.div([a.class("bg-indigo-100 p-4 rounded-2xl")], [key.render()])],
        )
      False -> element.none()
    },
  ])
}
