import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import eyg/website/page
import eygir/decode
import eygir/expression
import eygir/tree
import gleam/dict.{type Dict}
import gleam/javascript/promisex
import gleam/list
import gleam/option.{Some}
import gleroglero/outline
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/editable
import morph/lustre/components/key

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
  SelectNewProject
  Failed(String, List(String))
}

pub type State {
  State(
    status: Status,
    cache: sync.Sync,
    source: snippet.Snippet,
    other_projects: Dict(String, expression.Expression),
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
      #("json", expression.Integer(100)),
      #("foo", expression.Str("foo")),
    ])
  let state = State(Available, cache, snippet, others, False)
  #(state, effect.from(browser.do_sync(tasks, SyncMessage)))
}

pub type Message {
  UserClickedNew
  ProjectLoaded(name: String, source: expression.Expression)
  SnippetMessage(snippet.Message)
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
    ProjectLoaded(name, source) -> {
      let source = editable.from_expression(source)
      let snippet = snippet.init(source, [], [], state.cache)
      let state = State(..state, status: Available, source: snippet)
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
    tools(),
    case state.status {
      Available -> element.none()
      SelectNewProject ->
        modal(
          [
            h.div([a.class("hstack mb-2 gap-4")], [
              icon_button(outline.cursor_arrow_rays(), "Blank", [
                event.on_click(ProjectLoaded("", expression.Vacant(""))),
              ]),
              icon_button(outline.sparkles(), "Example", []),
              h.span([a.class("expand")], []),
            ]),
            h.h3([a.class("text-lg font-bold")], [element.text("Recent")]),
            h.ul(
              [a.class("list-inside list-disc")],
              list.map(dict.to_list(state.other_projects), fn(other) {
                let #(name, code) = other
                h.li([event.on_click(ProjectLoaded(name, code))], [
                  element.text(name),
                ])
              }),
            ),
          ],
          [],
          Primary,
        )
      Failed(title, reasons) -> {
        failure(title, reasons)
      }
    },
    header(),
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
      h.div([a.class("cover flex-grow w-full max-w-2xl p-6 bg-white")], [
        h.h2([a.class("texl-lg font-bold")], [element.text("ready ...")]),
        h.div([a.class("text-gray-700")], [
          element.text("Run and test your code. "),
          h.a([a.class("border-b border-indigo-700")], [element.text("help.")]),
        ]),
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

fn p(content) {
  h.p([], [element.text(content)])
}

fn li(content) {
  h.li([], [element.text(content)])
}

fn failure(title, reasons) {
  modal(
    [h.h3([a.class("text-lg")], [element.text(title)]), ..list.map(reasons, p)],
    [element.text("Ok")],
    Failure,
  )
}

type Emphasis {
  None
  Primary
  Failure
}

fn emphasis_background(emphasis) {
  case emphasis {
    None -> "bg-gray-100"
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
            [a.class("px-4 py-1 " <> emphasis_background(emphasis))],
            footer,
          ),
        ],
      ),
    ]),
  ])
}

fn header() {
  h.header([a.class("w-full py-4 px-6 text-xl bg-gray-800 text-white hstack")], [
    h.span([a.class("expand")], [
      // h.a([a.href("/"), a.class("font-bold")], [element.text("EYG")]),
      // h.span([a.class("")], [element.text(" - ")]),
      h.span([], [element.text("untitled")]),
      h.span([a.class("")], [element.text(" ")]),
      // h.button([a.class("border border-white")], [element.text("Save")]),
      h.button([a.class("border-b-2 border-purple-700 px-1 mx-1")], [
        element.text("Save"),
      ]),
      h.button(
        [
          a.class("border-b-2 border-purple-700 px-1 mx-1"),
          event.on_click(UserClickedNew),
        ],
        [element.text("New")],
      ),
    ]),
    h.span([a.class("p-1 border-b-2 border-purple-700 flex gap-2")], [
      h.span([], [element.text("publish")]),
      h.span([a.class("w-6 h-6")], [outline.arrow_top_right_on_square()]),
    ]),
  ])
}
