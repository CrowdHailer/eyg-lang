import eyg/hub/archive/client
import eyg/runtime/value
import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/output
import eyg/website/components/snippet
import eyg/website/page
import eygir/decode
import eygir/expression
import eygir/tree
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/option.{type Option, None, Some}
import gleroglero/outline
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import lustre/event
import midas/browser as midas_runner
import midas/task as t
import morph/analysis
import morph/editable
import morph/lustre/components/key
import morph/lustre/render
import morph/projection
import plinth/browser/credentials
import plinth/browser/crypto/subtle
import plinth/javascript/console
import snag.{type Snag, Snag}

// Using separate shell because other shell has openapi experiments

pub fn page(bundle) {
  page.app(Some("editor"), "eyg/website/editor", "client", bundle)
}

pub fn client() {
  let app = lustre.application(init, update, render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub type Status {
  Available
  Working(String)
  SelectNewProject
  PublishProject
  Failed(String, List(String))
}

pub type Credential {
  Credential(String)
}

pub type Remote {
  Remote(series: String, latest: Option(Int))
}

pub type ShellEntry {
  Executed(Option(snippet.Value), editable.Expression)
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
    // editor state
    status: Status,
    credentials: Option(Credential),
    // global cache
    cache: sync.Sync,
    // name of project in workspace
    name: String,
    source: snippet.Snippet,
    remote: Option(Remote),
    shell: Shell,
    // other saved projects
    other_projects: Dict(String, #(expression.Expression, Option(Remote))),
    // also global
    display_help: Bool,
  )
}

pub fn init(_) {
  let cache = sync.init(browser.get_origin())
  let source = editable.from_expression(expression.Vacant(""))
  let snippet = snippet.init(source, [], [], cache)
  let references = snippet.references(snippet)
  let #(cache, tasks) = sync.fetch_missing(cache, references)
  let others =
    dict.from_list([
      #("json", #(expression.Integer(100), Some(Remote("jsony", Some(2))))),
      #("foo", #(expression.Str("foo"), None)),
    ])
  let credentials = Some(Credential("SHA256:iKCaPnUxIMbKgs.."))
  let shell =
    Shell(
      [
        // reverse order
        Reloaded,
        Executed(
          Some(value.Integer(4)),
          editable.from_expression(expression.Apply(
            expression.Apply(
              expression.Builtin("int_add"),
              expression.Integer(2),
            ),
            expression.Integer(2),
          )),
        ),
      ],
      [#("x", value.Integer(4))],
      {
        let source = editable.from_expression(expression.Vacant(""))
        snippet.init(source, [], [], cache)
      },
    )
  let state =
    State(
      Available,
      credentials,
      cache,
      "",
      snippet,
      None,
      shell,
      others,
      False,
    )
  #(state, effect.from(browser.do_sync(tasks, SyncMessage)))
}

pub type Message {
  UserClickedNew
  UserInputForName(String)
  UserClickedSave
  UserClickedPublish
  UserClickedCancel
  UserClickedDismiss
  UserConfirmedNewCredential(String)
  UserConfirmedNewRemote(String)
  UserConfirmedPublish
  RemotePublishedPackage(series: String, version: Int)
  TaskFailed(Snag)
  ProjectLoaded(
    name: String,
    source: expression.Expression,
    remote: Option(Remote),
  )
  SnippetMessage(snippet.Message)
  ShellMessage(snippet.Message)
  SyncMessage(sync.Message)
}

fn dispatch_to_snippet(promise) {
  effect.from(fn(d) {
    promisex.aside(promise, fn(message) { d(SnippetMessage(message)) })
  })
}

fn dispatch_nothing(_promise) {
  effect.none()
}

pub fn update(state: State, message) {
  case message {
    UserClickedNew -> {
      let state = State(..state, status: SelectNewProject)
      #(state, effect.none())
    }
    UserInputForName(new) -> {
      let state = State(..state, name: new)
      #(state, effect.none())
    }
    UserClickedSave -> {
      let state = case state.name {
        "" -> State(..state, status: Failed("No name", []))
        _ -> {
          // TODO as go to disk, not publish to the backend, although maybe with JAZZ
          state
        }
      }
      #(state, effect.none())
    }
    UserClickedPublish -> {
      let state = State(..state, status: PublishProject)
      #(state, effect.none())
    }
    UserClickedCancel | UserClickedDismiss -> {
      let state = State(..state, status: Available)
      #(state, effect.none())
    }
    UserConfirmedNewRemote(remote) -> {
      let state = State(..state, remote: Some(Remote(remote, None)))
      #(state, effect.none())
    }
    UserConfirmedNewCredential(id) -> {
      let state = State(..state, credentials: Some(Credential(id)))
      let assert Ok(c) = credentials.from_navigator()
      io.debug(c)
      {
        let options =
          credentials.public_key_creation_options(
            <<0, 1, 2>>,
            credentials.ES256,
            "EYG",
            <<1, 2, 11, 22>>,
            "peters account",
            "Pete",
          )
        use r <- promise.await(credentials.create_public_key(c, options))
        case r {
          Ok(credentials.PublicKeyCredential(
            attachment,
            id,
            raw_id,
            response,
            type_,
          )) -> {
            io.debug(attachment)
            io.debug(id)
            io.debug(raw_id)
            io.debug(bit_array.base64_url_decode(id))
            io.debug(response)
            todo
          }
          Error(reason) -> console.log(reason)
        }
        // use r2 <- promise.await(credentials.get_public_key(c, <<2, 2>>))
        // console.log(r2)
        todo as "right"
      }
      #(state, effect.none())
    }
    UserConfirmedPublish -> {
      let state = State(..state, status: Working("publishing"))
      #(state, effect.from(publish(state)))
    }
    ProjectLoaded(name, source, remote) -> {
      let source = editable.from_expression(source)
      let snippet = snippet.init(source, [], [], state.cache)
      let state =
        State(
          ..state,
          status: Available,
          name: name,
          source: snippet,
          remote: remote,
        )
      #(state, effect.none())
    }
    TaskFailed(Snag(issue, causes)) -> {
      let state = State(..state, status: Failed(issue, causes))
      #(state, effect.none())
    }
    RemotePublishedPackage(series, version) -> {
      let remote = Remote(series, Some(version))
      let state = State(..state, status: Available, remote: Some(remote))
      #(state, effect.none())
    }
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
        snippet.Conclude(_, _) -> #(display_help, effect.none())
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
    // TODO I think we need to remove run from snippet and handle top level effects and types better
    // but top level types are checks of functions
    ShellMessage(message) -> {
      let #(snippet, eff) = snippet.update(state.shell.source, message)
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
        snippet.Conclude(_, _) -> #(display_help, effect.none())
      }
      let #(cache, tasks) = sync.fetch_all_missing(state.cache)
      let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      let state =
        State(
          ..state,
          shell: Shell(..state.shell, source: snippet),
          cache: cache,
          display_help: display_help,
        )
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

fn publish(state) {
  fn(d) {
    promise.map(midas_runner.run(do_publish(state)), fn(result) {
      case result {
        Ok(message) -> d(message)
        Error(reason) -> d(TaskFailed(reason))
      }
    })
    Nil
  }
}

fn do_publish(state: State) {
  let assert Some(Remote(series, latest)) = state.remote
  let next = case latest {
    Some(x) -> x + 1
    None -> 0
  }
  let source =
    projection.rebuild(state.source.source.0)
    |> editable.to_expression
  use Nil <- t.do(
    client.base_request("http://localhost:8080")
    |> client.publish(series, next, source),
  )
  t.done(RemotePublishedPackage(series, next))
}

fn icon_button(icon, text, attributes) {
  h.button(
    [
      a.class(
        "flex items-center px-2 py-1 border border-black font-medium hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-blue-300",
      ),
      ..attributes
    ],
    [h.div([a.class("h-5 w-5 mr-2")], [icon]), element.text(text)],
  )
}

pub fn render(state: State) {
  h.div([a.class("flex flex-col h-screen")], [
    // tools(),
    case state.status {
      Available -> element.none()
      Working(message) -> show_working(message)
      SelectNewProject -> select_project(state)
      PublishProject -> publish_project(state)
      Failed(title, reasons) -> failure(title, reasons)
    },
    header(state),
    h.div([a.class("hstack h-full gap-1 p-1 bg-gray-800")], [
      h.div(
        [
          a.class(
            "cover flex-grow flex flex-col justify-center w-full max-w-3xl font-mono bg-white",
          ),
        ],
        snippet.bare_render(state.source),
      )
        |> element.map(SnippetMessage),
      h.div([a.class("cover vstack w-full max-w-2xl bg-white")], [
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
              Executed(value, prog) ->
                h.div([a.class("w-full max-w-4xl")], [
                  h.div(
                    [a.class("px-2 whitespace-nowrap overflow-auto")],
                    render.statements(prog),
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
  ])
}

fn icon() {
  h.img([a.class("w-12"), a.src("https://eyg.run/assets/pea.webp")])
}

fn tools() {
  h.div(
    [a.class("fixed bottom-6 right-6 w-12 p-2 border border-black neo-shadow")],
    [h.span([a.class("")], [outline.wrench_screwdriver()])],
  )
}

fn show_working(message) {
  modal([p(message)], [], Neutral)
}

fn select_project(state: State) {
  modal(
    [
      h.div([a.class("hstack mb-2 gap-4")], [
        icon_button(outline.cursor_arrow_rays(), "Blank", [
          event.on_click(ProjectLoaded("", expression.Vacant(""), None)),
        ]),
        icon_button(outline.sparkles(), "Example", []),
        h.span([a.class("expand")], []),
      ]),
      h.h3([a.class("text-lg font-bold")], [element.text("Recent")]),
      h.ul(
        [a.class("list-inside list-disc")],
        list.map(dict.to_list(state.other_projects), fn(other) {
          let #(name, #(code, remote)) = other
          h.li([event.on_click(ProjectLoaded(name, code, remote))], [
            element.text(name),
          ])
        }),
      ),
    ],
    [],
    Primary,
  )
}

fn confirm_modal(content, action) {
  modal(
    content,
    [
      h.span([a.class("expand")], []),
      h.span([a.class("mx-2"), event.on_click(UserClickedCancel)], [
        element.text("Cancel"),
      ]),
      icon_button(outline.bolt(), "Confirm", [event.on_click(action)]),
    ],
    Primary,
  )
}

fn publish_project(state: State) {
  case state.credentials {
    None ->
      confirm_modal(
        [
          p("lets create a key"),
          icon_button(outline.finger_print(), "create new", []),
        ],
        UserConfirmedNewCredential("sos"),
      )
    Some(Credential(key)) -> {
      let #(_proj, exp, analysis) = state.source.source
      // snippet always does analysis
      let assert Some(analysis) = analysis
      case analysis.type_errors(analysis) {
        [] ->
          case state.remote {
            None -> {
              // Needs promise to create the new id
              // let project_id =
              //   subtle.digest(subtle.SHA1, bit_array.from_string(key))
              //   |> promise.map(fn(x) {
              //     let assert Ok(x) = x
              //     bit_array.base16_encode(x) |> io.debug
              //   })
              let project_id = "497389DB387427E504E21BF5737340A29B07F790"
              confirm_modal(
                [p(""), p("This project is published under #" <> project_id)],
                UserConfirmedNewRemote(project_id),
              )
            }
            Some(Remote(series, latest)) ->
              confirm_modal(
                [
                  h.h3([], [element.text("key: "), element.text(key)]),
                  p("project remote is @" <> series),
                  p(
                    "This will be the "
                    <> {
                      let next =
                        case latest {
                          Some(x) -> x + 1
                          None -> 0
                        }
                        |> int.to_string
                    }
                    <> "th release",
                  ),
                  p("check the changes to existing version"),
                ],
                UserConfirmedPublish,
              )
          }
        _ -> failure("Can't publish project with errors", [])
      }
    }
  }
}

fn p(content) {
  h.p([], [element.text(content)])
}

fn li(content) {
  h.li([], [element.text(content)])
}

fn failure(title, reasons) {
  modal(
    [h.h3([a.class("text-lg")], [element.text(title)]), ..list.map(reasons, p)],
    [
      h.span([a.class("expand")], []),
      h.span([event.on_click(UserClickedDismiss)], [element.text("Dismiss")]),
    ],
    Failure,
  )
}

type Emphasis {
  Neutral
  Primary
  Failure
}

fn emphasis_background(emphasis) {
  case emphasis {
    Neutral -> "bg-gray-100"
    Primary -> "bg-blue-200"
    Failure -> "bg-red-200"
  }
}

fn modal(content, footer, emphasis) {
  h.div([a.class("fixed inset-0 bg-gray-100 bg-opacity-40 vstack")], [
    h.div([a.class("w-full vstack")], [
      h.div(
        [a.class("w-full max-w-sm bg-white neo-shadow border-2 border-black")],
        [
          h.div([a.class("expand px-4 py-4 h-40")], content),
          h.div(
            [a.class("px-4 py-1 hstack " <> emphasis_background(emphasis))],
            footer,
          ),
        ],
      ),
    ]),
  ])
}

fn header(state: State) {
  h.header([a.class("w-full py-4 px-6 text-xl bg-gray-800 text-white hstack")], [
    h.span([a.class("expand")], [
      // h.a([a.href("/"), a.class("font-bold")], [element.text("EYG")]),
      // h.span([a.class("")], [element.text(" - ")]),
      // case state.name {
      //   "" -> h.span([], [
      //     element.text("untitled")])
      //   name -> h.span([], [element.text(name)])
      // },
      h.input([
        a.class("bg-gray-600"),
        a.value(state.name),
        a.placeholder("untitled"),
        event.on_input(UserInputForName),
      ]),
      h.span([a.class("")], [element.text(" ")]),
      // h.button([a.class("border border-white")], [element.text("Save")]),
      h.button(
        [
          a.class("border-b-2 border-purple-700 px-1 mx-1"),
          event.on_click(UserClickedSave),
        ],
        [element.text("Save")],
      ),
      h.button(
        [
          a.class("border-b-2 border-purple-700 px-1 mx-1"),
          event.on_click(UserClickedNew),
        ],
        [element.text("New")],
      ),
    ]),
    case state.remote {
      Some(Remote(hash, version)) -> short_hash(hash)
      None -> element.none()
    },
    h.span(
      [
        a.class("p-1 border-b-2 border-purple-700 flex gap-2"),
        event.on_click(UserClickedPublish),
      ],
      [
        h.span([], [element.text("publish")]),
        h.span([a.class("w-6 h-6")], [outline.arrow_top_right_on_square()]),
      ],
    ),
  ])
}

fn short_hash(hash) {
  h.span([], [element.text(hash)])
}
