import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/ir/tree as ir
import eyg/shell/examples
import eyg/sync/browser
import eyg/sync/sync
import gleam/int
import gleam/javascript/promisex
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import gleroglero/outline
import harness/impl/browser as harness
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/analysis
import morph/editable as e
import morph/input
import morph/picker
import mysig/asset
import mysig/html
import plinth/browser/document
import plinth/browser/element as pelement
import plinth/browser/window
import plinth/javascript/console
import website/components/output
import website/components/readonly
import website/components/snippet
import website/routes/common

pub fn app(module, func) {
  use script <- asset.do(asset.bundle(module, func))
  layout([
    h.div(
      [a.id("app"), a.style([#("position", "absolute"), #("inset", "0")])],
      [],
    ),
    h.script([a.src(asset.src(script))], ""),
  ])
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
        common.prism_style(),
        html.plausible("eyg.run"),
        h.style([], "html { height: 100%; }\nbody { min-height: 100%; }\n"),
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
  asset.done(element.to_document_string(content))
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
    readonly.Readonly,
  )
}

pub type ShellFailure {
  SnippetFailure(snippet.Failure)
  NoMoreHistory
}

pub type Shell {
  Shell(
    // config: spotless.Config,
    // situation: Situation,
    // cache: sync.Sync,
    failure: Option(ShellFailure),
    previous: List(ShellEntry),
    // display_help: Bool,
    // scope is on snippet
    // scope: snippet.Scope,
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
  let source = e.from_annotated(ir.vacant())
  // snippet has no effects, they run in the shell
  let snippet = snippet.init(source, [], [], cache)
  let shell =
    Shell(None, [], {
      let source = e.from_annotated(ir.vacant())
      // TODO update hardness to spotless
      snippet.init(source, [], harness.effects(), cache)
    })
  let state = State(cache, snippet, shell, False)
  #(state, effect.from(browser.do_load(SyncMessage)))
}

pub type Message {
  ToggleHelp
  ToggleFullscreen
  SnippetMessage(snippet.Message)
  UserClickedPrevious(e.Expression)
  ShellMessage(snippet.Message)
  PreviouseMessage(readonly.Message, Int)
  SyncMessage(sync.Message)
}

fn dispatch_to_snippet(promise) {
  effect.from(fn(d) {
    promisex.aside(promise, fn(message) { d(SnippetMessage(message)) })
  })
}

fn dispatch_to_previous(promise, i) {
  effect.from(fn(d) {
    promisex.aside(promise, fn(message) { d(PreviouseMessage(message, i)) })
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

fn close_many_previous(shell_entries) {
  list.map(shell_entries, fn(e) {
    let Executed(a, b, r) = e
    let r = readonly.Readonly(..r, status: readonly.Idle)
    Executed(a, b, r)
  })
}

fn close_all_previous(state: State) {
  let shell = state.shell
  let previous = close_many_previous(shell.previous)

  let shell = Shell(..shell, previous: previous)
  State(..state, shell: shell)
}

pub fn update(state: State, message) {
  case message {
    ToggleHelp -> #(
      State(..state, display_help: !state.display_help),
      effect.none(),
    )
    ToggleFullscreen -> #(
      state,
      effect.from(fn(_d) {
        let w = window.self()
        let doc = window.document(w)
        case document.fullscreen_element(doc) {
          Ok(_) -> document.exit_fullscreen(doc)
          Error(Nil) -> {
            let assert Ok(el) = document.get_element_by_id("app")
            pelement.request_fullscreen(el)
          }
        }
        Nil
      }),
    )

    SnippetMessage(message) -> {
      let #(snippet, eff) = snippet.update(state.source, message)
      let State(display_help: display_help, ..) = state
      let #(display_help, snippet_effect) = case eff {
        snippet.Nothing -> #(display_help, effect.none())
        snippet.Failed(_failure) -> {
          panic as "put on some state"
        }
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
    UserClickedPrevious(exp) -> {
      let shell = state.shell
      let scope = shell.source.scope
      let current = snippet.active(exp, scope, harness.effects(), state.cache)
      let shell = Shell(..shell, source: current)
      let state = State(..state, shell: shell)
      #(state, effect.none())
    }
    ShellMessage(message) -> {
      let state = close_all_previous(state)
      let shell = state.shell
      case snippet.user_message(message) {
        True -> Shell(..shell, failure: None)
        False -> shell
      }
      let #(source, eff) = snippet.update(shell.source, message)
      let #(shell, snippet_effect) = case eff {
        snippet.Nothing -> #(Shell(..shell, source: source), effect.none())
        snippet.Failed(failure) -> #(
          Shell(..shell, failure: Some(SnippetFailure(failure))),
          effect.none(),
        )

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
            [] -> #(Shell(..shell, failure: Some(NoMoreHistory)), effect.none())
            [Executed(_value, _effects, readonly), ..] -> {
              let scope = shell.source.scope
              let current =
                snippet.active(
                  readonly.source,
                  scope,
                  harness.effects(),
                  state.cache,
                )
              #(Shell(..shell, source: current), effect.none())
            }
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
            Executed(value, effects, readonly.new(snippet.source(shell.source))),
            ..shell.previous
          ]
          let source =
            snippet.active(e.Vacant, scope, harness.effects(), state.cache)
          let shell = Shell(..shell, source: source, previous: previous)
          #(shell, effect.none())
        }
      }
      let #(cache, tasks) = sync.fetch_all_missing(state.cache)
      let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      let state = State(..state, shell: shell, cache: cache)
      #(state, effect.batch([snippet_effect, sync_effect]))
    }
    PreviouseMessage(m, i) -> {
      let shell = state.shell
      let assert Ok(#(pre, executed, post)) =
        listx.split_around(shell.previous, i)
      let pre = close_many_previous(pre)
      let post = close_many_previous(post)
      let Executed(a, b, r) = executed
      let #(r, action) = readonly.update(r, m)
      let previous = listx.gather_around(pre, Executed(a, b, r), post)
      let effect = case action {
        readonly.Nothing -> effect.none()
        readonly.Fail(message) -> {
          console.warn(message)
          effect.none()
        }
        readonly.MoveAbove -> effect.none()
        readonly.MoveBelow -> effect.none()
        readonly.WriteToClipboard(text) ->
          dispatch_to_previous(readonly.write_to_clipboard(text), i)
      }
      let shell = Shell(..shell, previous: previous)
      #(State(..state, shell: shell), effect)
    }
    SyncMessage(message) -> {
      let cache = sync.task_finish(state.cache, message)
      let #(cache, tasks) = sync.fetch_all_missing(cache)
      let snippet = snippet.set_references(state.source, cache)
      let shell_source = snippet.set_references(state.shell.source, cache)
      let shell = Shell(..state.shell, source: shell_source)
      #(
        State(..state, source: snippet, shell: shell, cache: cache),
        effect.from(browser.do_sync(tasks, SyncMessage)),
      )
    }
  }
}

fn not_a_modal(content, dismiss: a) {
  element.fragment([
    h.div(
      [
        a.class("absolute inset-0 bg-gray-100 bg-opacity-70 vstack z-10"),
        a.style([#("backdrop-filter", "blur(4px)")]),
        event.on_click(dismiss),
      ],
      [],
    ),
    h.div(
      [
        a.class(
          // "-translate-x-1/2 -translate-y-1/2 absolute left-1/2 top-1/2 transform translate-x-1/2 w-full z-20",
          "absolute inset-0 flex flex-col justify-center z-20",
        ),
      ],
      content,
    ),
  ])
}

// https://stackoverflow.com/questions/17555682/height-100-or-min-height-100-for-html-and-body-elements
// needed on html and body
fn container(menu, page, open) {
  let min = case open {
    False -> "0"
    True -> "400px"
  }
  h.div(
    [
      // h-screen allows the address bar to hide
      a.class(
        "h-full overflow-hidden grid justify-center p-1 md:p-4 gap-1 md:gap-2 bg-gray-900",
      ),
      a.style([
        #("grid-template-columns", case open {
          True -> "max-content minmax(0px, 920px)"
          False -> "max-content minmax(0px, 920px)"
        }),
      ]),
    ],
    [
      h.div(
        [a.class("overflow-hidden flex flex-col justify-end text-white")],
        menu,
      ),
      h.div(
        [
          a.class(
            "overflow-auto bg-white relative flex flex-col rounded font-mono",
          ),
          a.style([#("min-width", min), #("overscroll-behavior-y", "contain")]),
        ],
        page,
      ),
    ],
  )
}

fn render_pallet(state: snippet.Snippet) {
  let snippet.Snippet(status: status, ..) = state
  case status {
    snippet.Editing(mode) ->
      case mode {
        snippet.Command -> element.none()

        snippet.Pick(picker, _rebuild) ->
          [
            h.div([a.class("flex-grow p-2 pb-12 h-full overflow-y-auto")], [
              h.div([a.class("font-bold")], [element.text("Label:")]),
              picker.render(picker),
              h.div(
                [
                  a.class(
                    "absolute bottom-0 right-4 flex gap-2 my-2 justify-end",
                  ),
                ],
                [
                  h.button(
                    [
                      a.class(
                        "py-1 px-2 bg-gray-200 rounded border border-black ",
                      ),
                      event.on_click(picker.Dismissed),
                    ],
                    [element.text("Cancel")],
                  ),
                  h.button(
                    [
                      a.class(
                        "py-1 px-2 bg-gray-300 rounded border border-black ",
                      ),
                      event.on_click(picker.Decided(picker.current(picker))),
                    ],
                    [element.text("Submit")],
                  ),
                ],
              ),
            ]),
          ]
          |> not_a_modal(picker.Dismissed)
          |> element.map(snippet.MessageFromPicker)

        snippet.EditText(value, _rebuild) ->
          render_text(value)
          |> list.wrap
          |> not_a_modal(input.KeyDown("Escape"))
          |> element.map(snippet.MessageFromInput)

        snippet.EditInteger(value, _rebuild) ->
          render_number(value)
          |> list.wrap()
          |> not_a_modal(input.KeyDown("Escape"))
          |> element.map(snippet.MessageFromInput)
      }

    snippet.Idle -> element.none()
  }
}

fn render_text(value) {
  render_user_input(value, "text", "Enter text:")
}

fn render_number(value) {
  let raw = case value {
    0 -> ""
    _ -> int.to_string(value)
  }
  render_user_input(raw, "number", "Enter number:")
}

fn render_user_input(raw, type_, message) {
  h.div([a.class("flex-grow m-2")], [
    h.div([a.class("font-bold")], [element.text(message)]),
    input.styled_input(
      raw,
      type_,
      "w-full outline-none border border-black rounded my-1 p-1",
      [],
    ),
    h.div([a.class("flex gap-2 my-2 justify-end")], [
      h.button(
        [
          a.class("py-1 px-2 bg-gray-200 rounded border border-black "),
          event.on_click(input.KeyDown("Escape")),
        ],
        [element.text("Cancel")],
      ),
      h.button(
        [
          a.class("py-1 px-2 bg-gray-300 rounded border border-black "),
          event.on_click(input.Submit),
        ],
        [element.text("Submit")],
      ),
    ]),
  ])
}

pub fn render(state: State) {
  let show = state.display_help
  container(
    render_menu_from_state(state)
      |> list.map(fn(e) {
        element.map(e, snippet.MessageFromMenu) |> element.map(ShellMessage)
      }),
    [
      render_pallet(state.shell.source) |> element.map(ShellMessage),
      h.div([a.class("absolute top-0 w-full bg-white")], [
        help_menu_button(state),
        fullscreen_menu_button(state),
      ]),
      h.div(
        [
          a.class("expand vstack flex-grow pt-10"),
          a.style([#("min-height", "0")]),
        ],
        case list.length(state.shell.previous) {
          x if x < 4 -> [
            h.div([a.class("px-2 text-gray-700 cover")], [
              h.h2([a.class("texl-lg font-bold")], [element.text("The shell")]),
              // h.p([], [element.text("Run and test your code here. ")]),
            // h.button([a.class("underline"), event.on_click(ToggleHelp)], [
            //   case state.display_help {
            //     True -> element.text("Hide help.")
            //     False -> element.text("Show help.")
            //   },
            // ]),
            ]),
            h.div([a.class("px-2 text-gray-700 cover")], [
              h.p([], [element.text("examples:")]),
              h.ul(
                [a.class("list-inside list-disc")],
                list.map(examples.examples(), fn(e) {
                  let #(source, message) = e
                  h.li([], [
                    h.button([event.on_click(UserClickedPrevious(source))], [
                      element.text(message),
                    ]),
                  ])
                }),
              ),
            ]),
          ]
          _ -> []
        },
      ),
      h.div([a.class("expand cover font-mono bg-gray-100 overflow-auto")], {
        let count = list.length(state.shell.previous) - 1
        list.index_map(list.reverse(state.shell.previous), fn(p, i) {
          let i = count - i
          case p {
            Executed(value, effects, readonly) ->
              h.div([a.class("mx-2 border-t border-gray-600 border-dashed")], [
                h.div([a.class("relative pr-8")], [
                  h.div([a.class("flex-grow whitespace-nowrap overflow-auto")], [
                    readonly.render(readonly)
                    |> element.map(PreviouseMessage(_, i)),
                  ]),
                  h.button(
                    [
                      a.class("absolute top-0 right-0 w-6"),
                      event.on_click(UserClickedPrevious(readonly.source)),
                    ],
                    [outline.arrow_path()],
                  ),
                ]),
                h.div([a.class("text-blue-700")], [
                  h.span([a.class("font-bold")], [element.text("effects ")]),
                  ..list.map(effects, fn(eff) {
                    h.span([], [element.text(eff.0), element.text(" ")])
                    // h.div([a.class("flex gap-1")], [
                    //   output.render(eff.1.0),
                    //   output.render(eff.1.1),
                    // ])
                  })
                ]),
                case value {
                  Some(value) ->
                    h.div([a.class(" max-h-60 overflow-auto")], [
                      h.span([a.class("font-bold")], [element.text("> ")]),
                      output.render(value),
                    ])
                  None -> element.none()
                },
              ])
          }
        })
      }),
      // snippet.render_current([], state.shell.source.run)
      //   |> element.map(ShellMessage),

      render_errors(state.shell.failure, state.shell.source),
      h.div(
        [
          a.class("cover border-t border-black font-mono bg-white grid"),
          a.style([
            #("min-height", "5rem"),
            #("grid-template-columns", "minmax(0px, 1fr) max-content"),
          ]),
        ],
        [
          h.div(
            [a.style([#("max-height", "65vh"), #("overflow-y", "scroll")])],
            [snippet.render_just_projection(state.shell.source, True)],
          ),
          h.button(
            [
              a.class(
                "inline-block w-8 md:w-12 bg-green-200 text-center text-xl",
              ),
              event.on_click(snippet.UserPressedCommandKey("Enter")),
            ],
            [outline.play_circle()],
          ),
        ],
      )
        |> element.map(ShellMessage),
    ],
    show,
  )
}

pub fn render_menu(status, projection, submenu, display_help) {
  let #(projection, _, _) = projection

  let #(top, subcontent) = snippet.menu_content(status, projection, submenu)
  case subcontent {
    None -> one_col_menu(display_help, top)
    Some(#(key, more)) -> two_col_menu(display_help, top, key, more)
  }
}

// The submenu is probably not part of the editor... yet
fn render_menu_from_state(state: State) {
  let State(shell: shell, ..) = state
  let snippet.Snippet(status: status, source: source, menu: menu, ..) =
    shell.source
  render_menu(status, source, menu, state.display_help)
}

fn help_menu_button(state: State) {
  h.button(
    [a.class("hover:bg-gray-200 px-2 py-1"), event.on_click(ToggleHelp)],
    [
      snippet.icon(
        outline.question_mark_circle(),
        "hide help",
        state.display_help,
      ),
    ],
  )
}

fn fullscreen_menu_button(state: State) {
  h.button(
    [a.class("hover:bg-gray-200 px-2 py-1"), event.on_click(ToggleFullscreen)],
    [snippet.icon(outline.tv(), "fullscreen", state.display_help)],
  )
}

fn one_col_menu(display_help, options) {
  [
    // help_menu_button(state),
    // same as grid below
    h.div(
      [
        a.class("grid overflow-y-auto"),
        a.style([#("grid-template-columns", "max-content max-content")]),
      ],
      [
        h.div(
          [a.class("flex flex-col justify-end text-gray-200 py-2")],
          list.map(options, fn(entry) {
            let #(i, text, k) = entry
            snippet.button(k, [snippet.icon(i, text, display_help)])
          }),
        ),
      ],
    ),
  ]
}

fn two_col_menu(display_help, top, active, sub) {
  [
    h.div(
      [
        a.class("grid overflow-y-auto overflow-x-hidden"),
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
              [snippet.icon(i, text, False)],
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
              [snippet.icon(i, text, display_help)],
            )
          }),
        ),
      ],
    ),
  ]
}

fn render_errors(failure, snippet: snippet.Snippet) {
  let #(_proj, _, analysis) = snippet.source
  let errors = case analysis {
    Some(analysis) -> analysis.type_errors(analysis)
    None -> []
  }

  case failure, errors {
    None, [] -> element.none()
    Some(SnippetFailure(failure)), _ ->
      h.div(
        [
          a.class("cover bg-red-300 px-2"),
          a.style([#("max-height", "25vh"), #("overflow-y", "scroll")]),
        ],
        [element.text(snippet.fail_message(failure))],
      )
    Some(NoMoreHistory), _ ->
      h.div(
        [
          a.class("cover bg-red-300 px-2"),
          a.style([#("max-height", "25vh"), #("overflow-y", "scroll")]),
        ],
        [element.text("No previous code to select")],
      )
    _, _ ->
      h.div(
        [
          a.class("cover bg-red-300 px-2"),
          a.style([#("max-height", "25vh"), #("overflow-y", "scroll")]),
        ],
        list.map(errors, fn(error) {
          let #(path, reason) = error
          case path, reason {
            // Vacant node at root or end of block are ignored.
            [], error.Todo | [_], error.Todo -> element.none()
            _, _ ->
              h.div(
                [event.on_click(ShellMessage(snippet.UserClickedPath(path)))],
                [element.text(debug.reason(reason))],
              )
          }
        }),
      )
  }
}
