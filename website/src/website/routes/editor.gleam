import eyg/sync/browser
import eyg/sync/sync
import eygir/expression
import gleam/io
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
import morph/editable as e
import morph/lustre/components/key
import morph/lustre/render
import morph/picker
import morph/projection as p
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
    e.Expression,
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
    open_submenu: Bool,
    display_help: Bool,
  )
}

pub fn init(_) {
  let cache = sync.init(browser.get_origin())
  let source = e.from_expression(expression.Vacant(""))
  let snippet = snippet.init(source, [], [], cache)
  let references = snippet.references(snippet)
  let #(cache, tasks) = sync.fetch_missing(cache, references)
  let shell =
    Shell([], [], {
      let source = e.from_expression(expression.Vacant(""))
      // TODO update hardness to spotless
      snippet.init(source, [], harness.effects(), cache)
    })
  let state = State(cache, snippet, shell, False, False)
  #(state, effect.from(browser.do_sync(tasks, SyncMessage)))
}

pub type Message {
  ToggleHelp
  OpenSubmenu
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
    OpenSubmenu -> #(
      State(..state, open_submenu: !state.open_submenu),
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
        snippet.Conclude(_, _, _) -> {
          io.debug("conclude")
          #(display_help, effect.none())
        }
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
      let state = State(..state, open_submenu: False)
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
          let source = snippet.active(e.Vacant(""), scope, [], state.cache)
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
        event.on_click(snippet.MessageFromPicker(picker.Dismissed)),
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

fn icon(image, text, display_help, active) {
  h.span([a.class("flex rounded"), a.style([#("align-items", "center")])], [
    h.span([a.class("inline-block w-6 text-center text-xl")], [image]),
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
    // case snippet.render_pallet(state.shell.source) {
    //   [] -> element.none()
    //   something ->
    //     modal(something)
    //     |> element.map(ShellMessage)
    // },
    // components.header(fn(_) { todo as "wire auth" }, None),
    h.div(
      [
        a.class("md:mx-auto grid gap-1 md:gap-2 p-2 md:p-6 h-full"),
        case state.display_help {
          False ->
            a.style([
              #("grid-template-columns", "max-content minmax(0px, 720px)"),
            ])
          True ->
            a.style([
              #("grid-template-columns", "max-content minmax(400px, 720px)"),
            ])
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
        render_menu(state),
        h.div(
          [
            a.class(
              "relative cover vstack w-full rounded-lg overflow-hidden bg-gray-100",
            ),
          ],
          [
            case snippet.render_pallet(state.shell.source) {
              [] -> element.none()
              something ->
                modal(something)
                |> element.map(ShellMessage)
            },
            h.div([a.class("expand vstack"), a.style([#("min-height", "0")])], case
              list.length(state.shell.previous)
            {
              0 -> [
                h.div([a.class("px-2 text-gray-700 cover")], [
                  h.h2([a.class("texl-lg font-bold")], [
                    element.text("The console"),
                  ]),
                  h.p([], [element.text("Run and test your code here. ")]),
                  h.button([a.class("underline"), event.on_click(ToggleHelp)], [
                    case state.display_help {
                      True -> element.text("Hide help.")
                      False -> element.text("Show help.")
                    },
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
                    h.div(
                      [a.class("mx-2 border-t border-gray-600 border-dashed")],
                      [
                        h.div(
                          [a.class("whitespace-nowrap overflow-auto")],
                          render.statements(prog),
                        ),
                        h.div(
                          [a.class("")],
                          list.map(effects, fn(eff) {
                            h.div([a.class("flex gap-1")], [
                              h.span([a.class("text-blue-700")], [
                                element.text(eff.0),
                              ]),
                              output.render(eff.1.0),
                              output.render(eff.1.1),
                            ])
                          }),
                        ),
                        case value {
                          Some(value) ->
                            h.div([a.class(" max-h-60 overflow-auto")], [
                              output.render(value),
                            ])
                          None -> element.none()
                        },
                      ],
                    )
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
            // snippet.render_current([], state.shell.source.run)
            //   |> element.map(ShellMessage),
            h.div([a.class("w-full text-right px-2")], [
              h.button(
                [
                  a.class("inline-block w-6 text-center text-xl"),
                  event.on_click(
                    ShellMessage(snippet.UserPressedCommandKey("Enter")),
                  ),
                ],
                [outline.play_circle()],
              ),
            ]),
            h.div(
              [
                a.class("cover font-mono bg-white"),
                a.style([#("min-height", "5rem")]),
              ],
              [snippet.render_just_projection(state.shell.source, True)],
            )
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

pub fn render_menu(state: State) {
  let cmd = fn(x) { ShellMessage(snippet.UserPressedCommandKey(x)) }
  let State(shell: shell, ..) = state
  let snippet.Snippet(status: status, source: source, ..) = shell.source
  let options = case status {
    snippet.Idle -> one_col_menu(state, [])
    snippet.Editing(snippet.Command(_)) -> {
      let #(#(focus, zoom), _, _) = source
      let top = case focus {
        // create
        p.Exp(e.Vacant(_)) -> [
          #(outline.equals(), "assign", cmd("e")),
          #(element.text("x"), "use variable", cmd("v")),
          #(outline.variable(), "insert function", cmd("f")),
          #(element.text("14"), "insert number", cmd("n")),
          #(outline.language(), "insert text", cmd("s")),
          #(element.text("[]"), "new list", cmd("l")),
          #(element.text("{}"), "new record", cmd("r")),
          #(outline.arrows_pointing_out(), "expand", cmd("a")),
          #(outline.squares_plus(), "more", OpenSubmenu),
        ]
        p.Exp(e.Variable(_)) -> [
          #(outline.pencil_square(), "edit", cmd("i")),
          #(element.text("..]"), "spread list", cmd(".")),
          #(element.text("..}"), "overwrite field", cmd("o")),
          #(element.text(".x"), "select field", cmd("g")),
          #(element.text("()"), "call function", cmd("c")),
          #(outline.tag(), "tag value", cmd("t")),
          #(outline.arrows_right_left(), "match", cmd("m")),
          #(outline.trash(), "delete", cmd("d")),
        ]
        p.Exp(e.Record(_, _)) -> [
          #(element.text(".."), "toggle spread", cmd("TOGGLE SPREAD")),
          #(outline.tag(), "tag value", cmd("t")),
          #(outline.trash(), "delete", cmd("d")),
        ]
        p.Exp(e.List(_, _)) -> [
          #(element.text(".."), "toggle spread", cmd("TOGGLE SPREAD")),
          #(outline.tag(), "tag value", cmd("t")),
          #(outline.trash(), "delete", cmd("d")),
        ]
        p.Assign(_, _, _, _, _) -> [
          #(outline.pencil_square(), "edit", cmd("i")),
          #(outline.document_arrow_up(), "assign above", cmd("E")),
        ]
        p.Select(_, _) -> [
          #(outline.pencil_square(), "edit", cmd("i")),
          #(outline.trash(), "delete", cmd("d")),
        ]
        _ -> []
      }

      case state.open_submenu {
        True ->
          two_col_menu(state, top, "more", [
            #(outline.bolt_slash(), "handle effect", cmd("h")),
            #(outline.bolt(), "perform effect", cmd("p")),
            #(outline.cog(), "builtins", cmd("j")),
          ])

        False -> one_col_menu(state, top)
      }
    }
    snippet.Editing(_) ->
      []
      |> one_col_menu(state, _)
  }
}

fn one_col_menu(state: State, options) {
  h.div([a.class("flex flex-col justify-end text-gray-200")], [
    h.div([a.class("flex-grow")], [
      h.button(
        [a.class("hover:bg-gray-800 px-2 py-1"), event.on_click(ToggleHelp)],
        [
          icon(
            outline.question_mark_circle(),
            "hide help",
            state.display_help,
            False,
          ),
        ],
      ),
    ]),
    ..list.map(options, fn(entry) {
      let #(i, text, k) = entry
      h.button([a.class("hover:bg-gray-800 px-2 py-1"), event.on_click(k)], [
        icon(i, text, state.display_help, False),
      ])
    })
  ])
}

fn two_col_menu(state: State, top, active, sub) {
  h.div([a.class("flex flex-col justify-end text-gray-200")], [
    h.div([a.class("")], [
      h.button(
        [a.class("hover:bg-gray-800 px-2 py-1"), event.on_click(ToggleHelp)],
        [
          icon(
            outline.question_mark_circle(),
            "hide help",
            state.display_help,
            False,
          ),
        ],
      ),
    ]),
    h.div(
      [
        a.class("grid flex-grow"),
        a.style([#("grid-template-columns", "max-content max-content")]),
      ],
      [
        h.div(
          [a.class("flex flex-col justify-end text-gray-200 py-2")],
          list.map(top, fn(entry) {
            let #(i, text, k) = entry
            h.button(
              [
                a.class("hover:bg-yellow-600 px-2 py-1 rounded-l-lg"),
                a.classes([#("bg-yellow-600", text == active)]),
                event.on_click(k),
              ],
              [icon(i, text, False, False)],
            )
          }),
        ),
        h.div(
          [
            a.class(
              "flex flex-col justify-end text-gray-200 bg-yellow-600 rounded-lg py-2",
            ),
          ],
          list.map(sub, fn(entry) {
            let #(i, text, k) = entry
            h.button(
              [a.class("hover:bg-yellow-500 px-2 py-1"), event.on_click(k)],
              [icon(i, text, state.display_help, False)],
            )
          }),
        ),
      ],
    ),
  ])
}
