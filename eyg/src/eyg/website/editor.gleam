import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import eyg/website/page
import eygir/decode
import eygir/tree
import gleam/list
import gleam/option.{None, Some}
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import morph/buffer
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

pub type State {
  State(cache: sync.Sync, source: snippet.Snippet, display_help: Bool)
}

const blank = "{\"0\":\"l\",\"l\":\"std\",\"v\":{\"0\":\"#\",\"l\":\"he4b05da\"},\"t\":{\"0\":\"l\",\"l\":\"http\",\"v\":{\"0\":\"#\",\"l\":\"he6fd05f0\"},\"t\":{\"0\":\"l\",\"l\":\"json\",\"v\":{\"0\":\"#\",\"l\":\"hbe004c96\"},\"t\":{\"0\":\"z\",\"c\":\"\"}}}}"

pub fn init(_) {
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

pub fn update(state: State, message) {
  case message {
    SnippetMessage(message) -> {
      let #(snippet, eff) = snippet.update(state.source, message)
      case snippet.action_error(snippet) {
        Some(buffer.NoKeyBinding("?")) -> {
          let state = State(..state, display_help: !state.display_help)
          #(state, effect.none())
        }
        _ -> {
          let #(cache, tasks) = sync.fetch_all_missing(state.cache)
          let state = State(..state, source: snippet, cache: cache)
          #(state, case eff {
            None -> {
              effect.from(browser.do_sync(tasks, SyncMessage))
            }
            Some(f) ->
              effect.from(fn(d) {
                let d = fn(m) { d(SnippetMessage(m)) }
                f(d)
              })
          })
        }
      }
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
