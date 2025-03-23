import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/ir/tree as ir
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/option.{None, Some}
import gleroglero/outline
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
import website/components/autocomplete
import website/components/examples
import website/components/output
import website/components/readonly
import website/components/runner
import website/components/shell
import website/components/simple_debug
import website/components/snippet
import website/components/vertical_menu
import website/harness/browser as harness
import website/routes/common
import website/sync/client

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
        h.style([], "html { height: 100%; }\nbody { min-height: 100%; }\n"),
      ],
      common.page_meta(
        "/",
        "EYG",
        "EYG is a programming language for predictable, useful and most of all confident development.",
      ),
      common.diagnostics(),
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

pub type State {
  State(
    sync: client.Client,
    source: snippet.Snippet,
    shell: shell.Shell,
    display_help: Bool,
  )
}

pub fn init(_) {
  let #(client, sync_task) = client.default()
  let source = e.from_annotated(ir.vacant())
  let shell = shell.init(harness.effects(), client.cache)
  let snippet = snippet.init(source)
  let state = State(client, snippet, shell, False)
  #(state, client.lustre_run(sync_task, SyncMessage))
}

pub type Message {
  ToggleHelp
  ToggleFullscreen
  SnippetMessage(snippet.Message)
  ShellMessage(shell.Message)
  SyncMessage(client.Message)
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

fn dispatch_nothing(func) {
  effect.from(fn(_dispatch) { func() })
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
        snippet.NewCode -> #(
          display_help,
          dispatch_nothing(snippet.focus_on_buffer),
        )
        snippet.Confirm -> #(display_help, effect.none())
        snippet.Failed(_failure) -> #(display_help, effect.none())
        snippet.ReturnToCode -> #(
          display_help,
          dispatch_nothing(snippet.focus_on_buffer),
        )
        snippet.FocusOnInput -> #(
          display_help,
          dispatch_nothing(snippet.focus_on_input),
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
      }
      // let #(cache, tasks) = sync.fetch_all_missing(state.cache)
      // let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      io.debug("We need the sync effect")
      let state =
        State(
          ..state,
          source: snippet,
          // cache: cache,
          display_help: display_help,
        )
      #(state, effect.batch([snippet_effect]))
    }
    ShellMessage(message) -> {
      let #(shell, shell_effect) = shell.update(state.shell, message)
      let references =
        snippet.references(state.source)
        |> list.append(snippet.references(shell.source))
      let #(sync, sync_task) = client.fetch_fragments(state.sync, references)
      let state = State(..state, sync:, shell:)
      let shell_effect = case shell_effect {
        shell.Nothing -> effect.none()
        shell.RunExternalHandler(ref, thunk) ->
          dispatch_to_shell(
            promise.map(thunk(), fn(reply) {
              shell.RunnerMessage(runner.HandlerCompleted(ref, reply))
            }),
          )
        shell.WriteToClipboard(text) ->
          dispatch_to_shell(shell.write_to_clipboard(text))
        shell.ReadFromClipboard ->
          dispatch_to_shell(shell.read_from_clipboard())
        shell.FocusOnCode -> dispatch_nothing(snippet.focus_on_buffer)
        shell.FocusOnInput -> dispatch_nothing(snippet.focus_on_input)
      }
      #(
        state,
        effect.batch([shell_effect, client.lustre_run(sync_task, SyncMessage)]),
      )
    }
    SyncMessage(message) -> {
      let State(sync:, shell:, ..) = state
      let #(sync, effect) = client.update(sync, message)
      let #(shell, shell_effect) =
        shell.update(shell, shell.CacheUpdate(sync.cache))
      let shell_effect = case shell_effect {
        shell.Nothing -> effect.none()
        shell.RunExternalHandler(ref, thunk) ->
          dispatch_to_shell(
            promise.map(thunk(), fn(reply) {
              shell.RunnerMessage(runner.HandlerCompleted(ref, reply))
            }),
          )
        shell.WriteToClipboard(text) ->
          dispatch_to_shell(shell.write_to_clipboard(text))
        shell.ReadFromClipboard ->
          dispatch_to_shell(shell.read_from_clipboard())
        shell.FocusOnCode -> dispatch_nothing(snippet.focus_on_buffer)
        shell.FocusOnInput -> dispatch_nothing(snippet.focus_on_input)
      }
      let state = State(..state, sync:, shell:)
      #(
        state,
        effect.batch([client.lustre_run(effect, SyncMessage), shell_effect]),
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
        snippet.SelectRelease(state, _) ->
          autocomplete.render(state, snippet.release_to_option)
          |> list.wrap
          |> not_a_modal(autocomplete.UserPressedEscape)
          |> element.map(snippet.SelectReleaseMessage)

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
        element.map(e, snippet.MessageFromMenu)
        |> element.map(shell.CurrentMessage)
        |> element.map(ShellMessage)
      }),
    [
      render_pallet(state.shell.source)
        |> element.map(shell.CurrentMessage)
        |> element.map(ShellMessage),
      h.div([a.class("absolute top-0 w-full bg-white")], [
        help_menu_button(state),
        fullscreen_menu_button(state),
      ]),
      h.div([a.class("h-full")], [
        render_shell(state.shell)
        |> element.map(ShellMessage),
        // h.div([], [element.text("hello")]),
      ]),
    ],
    show,
  )
}

fn render_shell(shell: shell.Shell) {
  h.div([a.class("h-full flex flex-col")], [
    h.div(
      [
        a.class("expand vstack flex-grow pt-10"),
        a.style([#("min-height", "0")]),
      ],
      case list.length(shell.previous) {
        x if x < 4 -> [
          h.div([a.class("px-2 text-gray-700 cover")], [
            h.h2([a.class("texl-lg font-bold")], [element.text("The shell")]),
          ]),
          h.div([a.class("px-2 text-gray-700 cover")], [
            h.p([], [element.text("examples:")]),
            h.ul(
              [a.class("list-inside list-disc")],
              list.map(examples.examples(), fn(e) {
                let #(source, message) = e
                h.li([], [
                  h.button([event.on_click(shell.ParentSetSource(source))], [
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
      let count = list.length(shell.previous) - 1
      list.index_map(list.reverse(shell.previous), fn(p, i) {
        let i = count - i
        case p {
          shell.Executed(value, effects, readonly) ->
            h.div([a.class("mx-2 border-t border-gray-600 border-dashed")], [
              h.div([a.class("relative pr-8")], [
                h.div([a.class("flex-grow whitespace-nowrap overflow-auto")], [
                  readonly.render(readonly)
                  |> element.map(shell.PreviousMessage(i, _)),
                ]),
                h.button(
                  [
                    a.class("absolute top-0 right-0 w-6"),
                    event.on_click(shell.UserClickedPrevious(1)),
                  ],
                  [outline.arrow_path()],
                ),
              ]),
              case effects {
                [] -> element.none()
                _ ->
                  h.div([a.class("text-blue-700")], [
                    h.span([a.class("font-bold")], [element.text("effects ")]),
                    ..list.map(effects, fn(eff) {
                      let #(label, _) = eff
                      h.span([], [element.text(label), element.text(" ")])
                      // h.div([a.class("flex gap-1")], [
                      //   output.render(eff.1.0),
                      //   output.render(eff.1.1),
                      // ])
                    })
                  ])
              },
              case value {
                Some(value) ->
                  h.div([a.class(" max-h-60 overflow-auto")], [
                    // would need to be flex to show inline
                    // h.span([a.class("font-bold")], [element.text("> ")]),
                    output.render(value),
                  ])
                None -> element.none()
              },
            ])
        }
      })
    }),
    render_errors(shell.failure, shell.source),
    h.div(
      [
        a.class("cover border-t border-black font-mono bg-white grid"),
        a.style([
          #("min-height", "5rem"),
          #("grid-template-columns", "minmax(0px, 1fr) max-content"),
        ]),
      ],
      [
        h.div([a.style([#("max-height", "65vh"), #("overflow-y", "scroll")])], [
          snippet.render_just_projection(shell.source, True),
        ]),
        case shell.runner {
          runner.Runner(continue: False, ..) ->
            h.button(
              [
                a.class(
                  "inline-block w-8 md:w-12 bg-green-200 text-center text-xl",
                ),
                event.on_click(snippet.UserPressedCommandKey("Enter")),
              ],
              [outline.play_circle()],
            )
          runner.Runner(awaiting: Some(_), ..) ->
            h.span(
              [
                a.class(
                  "inline-block w-8 md:w-12 bg-blue-200 text-center text-xl",
                ),
              ],
              [outline.arrow_path()],
            )
          runner.Runner(return: Error(#(reason, _, _, _)), ..) ->
            h.span(
              [
                a.class(
                  "inline-block w-8 md:w-12 bg-red-200 text-center text-xl",
                ),
                a.title(simple_debug.reason_to_string(reason)),
              ],
              [outline.exclamation_circle()],
            )
          _ ->
            h.button(
              [
                a.class(
                  "inline-block w-8 md:w-12 bg-green-200 text-center text-xl",
                ),
                event.on_click(snippet.UserPressedCommandKey("Enter")),
              ],
              [outline.play_circle()],
            )
        },
      ],
    )
      |> element.map(shell.CurrentMessage),
  ])
}

pub fn render_menu(status, projection, submenu, display_help) {
  let #(top, subcontent) = snippet.menu_content(status, projection, submenu)
  case subcontent {
    None -> vertical_menu.one_col_menu(display_help, top)
    Some(#(key, more)) ->
      vertical_menu.two_col_menu(display_help, top, key, more)
  }
}

// The submenu is probably not part of the editor... yet
fn render_menu_from_state(state: State) {
  let State(shell: shell, ..) = state
  let snippet.Snippet(status: status, projection: projection, menu: menu, ..) =
    shell.source
  render_menu(status, projection, menu, state.display_help)
}

fn help_menu_button(state: State) {
  h.button(
    [a.class("hover:bg-gray-200 px-2 py-1"), event.on_click(ToggleHelp)],
    [
      vertical_menu.icon(
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
    [vertical_menu.icon(outline.tv(), "fullscreen", state.display_help)],
  )
}

fn render_errors(failure, snippet: snippet.Snippet) {
  let errors = case snippet.analysis {
    Some(analysis) -> analysis.type_errors(analysis)
    None -> []
  }

  case failure, errors {
    None, [] -> element.none()
    Some(shell.SnippetFailure(failure)), _ ->
      h.div(
        [
          a.class("cover bg-red-300 px-2"),
          a.style([#("max-height", "25vh"), #("overflow-y", "scroll")]),
        ],
        [element.text(snippet.fail_message(failure))],
      )
    Some(shell.NoMoreHistory), _ ->
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
                [
                  event.on_click(
                    snippet.UserClickedPath(path)
                    |> shell.CurrentMessage,
                  ),
                ],
                [element.text(debug.reason(reason))],
              )
          }
        }),
      )
  }
}
