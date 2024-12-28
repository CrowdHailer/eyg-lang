import eyg/sync/browser
import eyg/sync/sync
import eygir/expression
import gleam/javascript/promisex
import gleam/list
import gleam/option.{type Option, None, Some}
import gleroglero/outline
import harness/impl/browser as harness
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import lustre/event
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
  ToggleHelp
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
    ToggleHelp -> #(
      State(..state, display_help: !state.display_help),
      effect.none(),
    )
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
            [Executed(_value, _effects, exp), ..] -> {
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
            [Reloaded, Executed(_value, _effects, exp), ..] -> {
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

fn modal(content) {
  element.fragment([
    h.div(
      [
        a.class("fixed inset-0 bg-gray-100 bg-opacity-40 vstack z-10"),
        // event.on_click(Cancel),
      ],
      [],
    ),
    h.div(
      [
        a.class(
          "-translate-x-1/2 -translate-y-1/2 fixed left-1/2 max-w-md top-1/2 transform translate-x-1/2 w-full z-20",
        ),
      ],
      [
        h.div(
          [a.class("w-full max-w-md bg-white neo-shadow border-2 border-black")],
          content,
        ),
      ],
    ),
  ])
}

fn icon(image, text, display_help) {
  h.span([a.class("flex"), a.style([#("align-items", "center")])], [
    h.span([a.class("inline-block w-5 text-center text-xl ")], [image]),
    case display_help {
      True ->
        h.span([a.class("ml-2 border-l border-opacity-25 pl-2")], [
          element.text(text),
        ])
      False -> element.none()
    },
  ])
}

pub fn render(state: State) {
  h.div([a.class("flex flex-col h-screen bg-gray-900 overflow-hidden")], [
    case snippet.render_pallet(state.shell.source) {
      [] -> element.none()
      something ->
        modal(something)
        |> element.map(ShellMessage)
    },
    // components.header(fn(_) { todo as "wire auth" }, None),
    h.div(
      [
        a.class("mx-auto grid gap-1 md:gap-2 p-2 md:p-6 h-full"),
        case state.display_help {
          False ->
            a.style([#("grid-template-columns", "2.5rem minmax(400px, 720px)")])
          True ->
            a.style([#("grid-template-columns", "10rem minmax(400px, 720px)")])
        },
      ],
      [
        // h.div(
        //   [
        //     a.class(
        //       "flex-grow flex flex-col justify-center w-full rounded-xl border-2 border-black bg-white overflow-hidden neo-shadow font-mono ",
        //     ),
        //   ],
        //   snippet.bare_render(state.source),
        // )
        //   |> element.map(SnippetMessage),
        h.div([a.class("flex flex-col justify-end text-gray-200")], [
          h.div([a.class("flex-grow")], [
            h.button(
              [
                a.class("hover:bg-gray-800 px-2 py-1"),
                event.on_click(ToggleHelp),
              ],
              [
                icon(
                  outline.question_mark_circle(),
                  "hide help",
                  state.display_help,
                ),
              ],
            ),
          ]),
          ..list.map(
            [
              #(outline.bolt_slash(), "handle effect", "h"),
              #(outline.bolt(), "perform effect", "p"),
              #(element.text("x"), "use variable", "v"),
              #(outline.variable(), "insert function", "f"),
              #(element.text("14"), "insert number", "n"),
              #(outline.language(), "insert text", "s"),
              #(outline.tag(), "tag value", "t"),
              #(outline.arrows_pointing_out(), "expand", "a"),
            ],
            fn(entry) {
              let #(i, text, k) = entry
              h.button(
                [
                  a.class("hover:bg-gray-800 px-2 py-1"),
                  event.on_click(ShellMessage(snippet.UserPressedCommandKey(k))),
                ],
                [icon(i, text, state.display_help)],
              )
            },
          )
        ]),
        h.div(
          [a.class("cover vstack w-full rounded-lg overflow-hidden bg-white")],
          [
            h.div([a.class("expand vstack"), a.style([#("min-height", "0")])], case
              list.length(state.shell.previous)
            {
              0 -> [
                h.h2([a.class("texl-lg font-bold")], [
                  element.text("The console"),
                ]),
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
            h.div([a.class("cover font-mono")], [
              snippet.render_just_projection(state.shell.source, True),
            ])
              |> element.map(ShellMessage),
          ],
        ),
      ],
    ),
    // case state.display_help {
  //   True ->
  //     h.div(
  //       [
  //         a.class(
  //           "bottom-0 fixed flex flex-col justify-around mr-10 right-0 top-0",
  //         ),
  //       ],
  //       [h.div([a.class("bg-indigo-100 p-4 rounded-2xl")], [key.render()])],
  //     )
  //   False -> element.none()
  // },
  ])
}
