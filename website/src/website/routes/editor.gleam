import eyg/analysis/type_/binding/debug
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
import morph/analysis
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

// https://stackoverflow.com/questions/17555682/height-100-or-min-height-100-for-html-and-body-elements
// needed on html and body
fn container(menu, page, open) {
  let min = case open {
    False -> "0"
    True -> "400px"
  }
  h.div(
    [
      a.class(
        "h-full overflow-hidden grid justify-center p-1 md:p-4 gap-1 md:gap-4 bg-gray-900",
      ),
      a.style([
        #("grid-template-columns", case open {
          True -> "max-content minmax(0px, 720px)"
          False -> "max-content minmax(0px, 720px)"
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
          a.class("overflow-auto bg-white flex flex-col rounded"),
          a.style([#("min-width", min)]),
        ],
        page,
      ),
    ],
  )
  // h.div([a.class("h-full w-full bg-gray-900 text-white overflow-hidden")], [
  //   // case snippet.render_pallet(state.shell.source) {
  //   //   [] -> element.none()
  //   //   something ->
  //   //     modal(something)
  //   //     |> element.map(ShellMessage)
  //   // },
  //   // components.header(fn(_) { todo as "wire auth" }, None),
  //   h.div(
  //     [
  //       a.class("md:mx-auto grid gap-1 flex justify-center md:gap-2 h-full"),
  //     ],
  //     [menu, page],
  //   ),
  // ])
}

pub fn render(state: State) {
  let show = state.display_help
  container(
    render_menu(state),
    [
      case snippet.render_pallet(state.shell.source) {
        [] -> element.none()
        something ->
          modal(something)
          |> element.map(ShellMessage)
      },
      h.div(
        [a.class("expand vstack flex-grow"), a.style([#("min-height", "0")])],
        case list.length(state.shell.previous) {
          0 -> [
            h.div([a.class("px-2 text-gray-700 cover")], [
              h.h2([a.class("texl-lg font-bold")], [element.text("The console")]),
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
        },
      ),
      h.div(
        [a.class("expand cover font-mono bg-gray-100 overflow-auto")],
        list.map(list.reverse(state.shell.previous), fn(p) {
          case p {
            Executed(value, effects, prog) ->
              h.div([a.class("mx-2 border-t border-gray-600 border-dashed")], [
                h.div(
                  [a.class("whitespace-nowrap overflow-auto")],
                  render.statements(prog),
                ),
                h.div(
                  [a.class("")],
                  list.map(effects, fn(eff) {
                    h.div([a.class("flex gap-1")], [
                      h.span([a.class("text-blue-700")], [element.text(eff.0)]),
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
              ])
            Reloaded ->
              h.div(
                [a.class("separator mx-12 mt-1 border-blue-400 text-blue-400")],
                [element.text("Reloaded")],
              )
          }
        }),
      ),
      // snippet.render_current([], state.shell.source.run)
      //   |> element.map(ShellMessage),

      render_errors(state.shell.source),
      h.div(
        [
          a.class("cover border-t border-black font-mono bg-white grid"),
          a.style([
            #("min-height", "5rem"),
            #("grid-template-columns", "minmax(0px, 1fr) max-content"),
          ]),
        ],
        [
          h.div([], [snippet.render_just_projection(state.shell.source, True)]),
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

fn cmd(x) {
  ShellMessage(snippet.UserPressedCommandKey(x))
}

fn assign() {
  #(outline.equals(), "assign", cmd("e"))
}

fn assign_before() {
  #(outline.document_arrow_up(), "assign above", cmd("E"))
}

fn use_variable() {
  #(element.text("x"), "use variable", cmd("v"))
}

fn insert_function() {
  #(outline.variable(), "insert function", cmd("f"))
}

fn insert_number() {
  #(element.text("14"), "insert number", cmd("n"))
}

fn insert_text() {
  #(outline.language(), "insert text", cmd("s"))
}

fn new_list() {
  #(element.text("[]"), "new list", cmd("l"))
}

fn new_record() {
  #(element.text("{}"), "new record", cmd("r"))
}

fn expand() {
  #(outline.arrows_pointing_out(), "expand", cmd("a"))
}

fn more() {
  #(outline.squares_plus(), "more", OpenSubmenu)
}

fn edit() {
  #(outline.pencil_square(), "edit", cmd("i"))
}

fn spread_list() {
  #(element.text("..]"), "spread list", cmd("."))
}

fn overwrite_field() {
  #(element.text("..}"), "overwrite field", cmd("o"))
}

fn select_field() {
  #(element.text(".x"), "select field", cmd("g"))
}

fn call_function() {
  #(element.text("(_)"), "call function", cmd("c"))
}

fn call_with() {
  #(element.text("_()"), "call as argument", cmd("w"))
}

fn tag_value() {
  #(outline.tag(), "tag value", cmd("t"))
}

fn match() {
  #(outline.arrows_right_left(), "match", cmd("m"))
}

fn toggle_spread() {
  #(element.text(".."), "toggle spread", cmd("TOGGLE SPREAD"))
}

fn delete() {
  #(outline.trash(), "delete", cmd("d"))
}

// The submenu is probably not part of the editor... yet
pub fn render_menu(state: State) {
  let State(shell: shell, ..) = state
  let snippet.Snippet(status: status, source: source, ..) = shell.source
  case status {
    snippet.Idle -> one_col_menu(state, [])
    snippet.Editing(snippet.Command(_)) -> {
      let #(#(focus, zoom), _, _) = source
      let top = case focus {
        // create
        p.Exp(exp) ->
          case exp {
            e.Variable(_) | e.Reference(_) -> [
              edit(),
              spread_list(),
              overwrite_field(),
              select_field(),
              tag_value(),
              match(),
              call_function(),
              call_with(),
            ]
            e.Call(_, _) -> [
              new_list(),
              new_record(),
              call_function(),
              call_with(),
            ]
            e.Function(_, _) -> [
              new_list(),
              new_record(),
              insert_function(),
              call_with(),
            ]
            e.Block(_, _, _) -> []
            e.Vacant(_) -> [
              use_variable(),
              insert_function(),
              insert_number(),
              insert_text(),
              new_list(),
              new_record(),
              expand(),
              more(),
            ]
            e.Integer(_)
            | e.Binary(_)
            | e.String(_)
            | e.Perform(_)
            | e.Deep(_)
            | e.Shallow(_) -> [edit(), new_list(), new_record(), call_with()]
            e.Builtin(_) -> [
              edit(),
              new_list(),
              new_record(),
              call_function(),
              call_with(),
            ]
            e.List(_, _) | e.Record(_, _) -> [
              toggle_spread(),
              new_list(),
              new_record(),
              call_with(),
            ]
            e.Select(_, _) -> [edit(), new_list(), new_record(), call_with()]
            e.Tag(_) -> [edit(), new_list(), new_record(), call_with()]
            // match open match
            e.Case(_, _, _) -> [new_list(), new_record(), call_with()]
          }
          |> list.append([assign()], _)
          |> list.append([delete()])

        p.Assign(_, _, _, _, _) -> [edit(), assign_before()]
        p.Select(_, _) -> [edit(), delete()]
        p.FnParam(_, _, _, _) -> [edit(), delete()]
        p.Label(_, _, _, _, _) -> [edit(), delete()]
        p.Match(_, _, _, _, _, _) -> [edit(), delete()]
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

fn help_menu_button(state: State) {
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
  ])
}

fn one_col_menu(state: State, options) {
  [
    help_menu_button(state),
    // same as grid below
    h.div(
      [a.class("flex flex-col justify-end py-2 overflow-y-auto")],
      list.map(options, fn(entry) {
        let #(i, text, k) = entry
        h.button([a.class("hover:bg-gray-800 px-2 py-1"), event.on_click(k)], [
          icon(i, text, state.display_help, False),
        ])
      }),
    ),
  ]
}

fn two_col_menu(state: State, top, active, sub) {
  [
    help_menu_button(state),
    h.div(
      [
        a.class("grid flex-grow overflow-y-auto"),
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
  ]
}

fn render_errors(snippet: snippet.Snippet) {
  let #(proj, _, analysis) = snippet.source
  let errors = case analysis {
    Some(analysis) -> analysis.type_errors(analysis)
    None -> []
  }

  case snippet.status, errors {
    snippet.Editing(snippet.Command(None)), [] -> element.none()
    snippet.Editing(snippet.Command(Some(failure))), _ ->
      h.div([a.class("cover bg-red-300 px-2")], [
        element.text(snippet.fail_message(failure)),
      ])
    _, _ ->
      h.div(
        [a.class("cover bg-red-300 px-2")],
        list.map(errors, fn(error) {
          let #(path, reason) = error
          h.div([event.on_click(ShellMessage(snippet.UserClickedPath(path)))], [
            element.text(debug.reason(reason)),
          ])
        }),
      )
  }
}
