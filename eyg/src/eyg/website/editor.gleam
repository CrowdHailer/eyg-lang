import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import eyg/website/page
import eygir/decode
import eygir/tree
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/option.{Some}
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/editable
import morph/lustre/components/key
import plinth/browser/file_system as fs
import plinth/browser/storage

pub fn page(bundle) {
  page.app(Some("editor"), "eyg/website/editor", "client", bundle)
}

pub fn client() {
  let app = lustre.application(init, update, render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub type State {
  State(cache: sync.Sync, source: snippet.Snippet, display_help: Bool)
}

const blank = "{\"0\":\"z\",\"c\":\"\"}"

fn load_local() {
  let assert Ok(storage) = storage.get()
  use root <- promise.await(storage.get_directory(storage))
  io.debug(root)
  let assert Ok(root) = root
  use dir <- promise.await(fs.get_directory_handle(root, "projects", True))
  let assert Ok(dir) =
    dir
    |> io.debug
  io.debug(fs.name(dir))
  use result <- promise.await(fs.all_entries(dir))
  let assert Ok(#(projects, _)) = result
  let projects = array.to_list(projects)
  io.debug(projects |> list.map(fn(x) { #(fs.name(x), x) }))
  use dir <- promise.await(fs.remove_entry(dir, "mooble", True))
  let assert Ok(dir) =
    dir
    |> io.debug

  promise.resolve(Nil)
}

pub fn init(_) {
  load_local()

  let cache = sync.init(browser.get_origin())
  let assert Ok(source) = decode.from_json(blank)
  let source =
    editable.from_expression(source)
    |> editable.open_all
  let snippet = snippet.init(source, [], [], cache)
  let references = snippet.references(snippet)
  let #(cache, tasks) = sync.fetch_missing(cache, references)
  let state = State(cache, snippet, True)
  #(state, effect.from(browser.do_sync(tasks, SyncMessage)))
}

pub type Message {
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
        State(source: snippet, cache: cache, display_help: display_help)
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
    h.div([a.class("w-full py-2 px-6 text-xl text-gray-500")], [
      h.a([a.href("/"), a.class("font-bold")], [element.text("EYG")]),
      h.span([a.class("")], [element.text(" - Editor")]),
    ]),
    h.div([a.class("w-full py-2 px-4 bg-gray-500")], [
      h.select(
        [
          event.on_input(fn(x) {
            io.debug(x)
            // Error([])
            todo
          }),
        ],
        [h.option([a.value("foo")], "me"), h.option([a.value("eyg")], "eyg")],
      ),
      h.span([], [element.text("unpublished")]),
    ]),
    h.div([a.class("grid grid-cols-2 h-full")], [
      h.div(
        [
          a.class(
            "flex-grow flex flex-col justify-center w-full max-w-3xl font-mono px-6",
          ),
        ],
        [snippet.render_editor(state.source)],
      ),
      h.div([a.class("leading-none p-4 text-gray-500")], [
        h.pre(
          [],
          list.map(
            tree.lines(editable.to_expression(snippet.source(state.source))),
            fn(x) { h.div([], [h.pre([], [element.text(x)])]) },
          ),
        ),
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
  |> element.map(SnippetMessage)
}
