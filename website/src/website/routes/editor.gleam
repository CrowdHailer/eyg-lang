import eyg/sync/browser
import eyg/sync/sync
import eygir/expression
import eygir/tree
import gleam/javascript/promisex
import gleam/list
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import midas/task as t
import morph/editable
import morph/lustre/components/key
import mysig/asset
import mysig/html
import mysig/layout
import mysig/neo
import mysig/route
import website/components/snippet
import website/routes/common

pub fn app(module, func, bundle) {
  use script <- t.do(t.bundle(module, func))
  use script <- t.do(asset.js("page", script))
  layout([html.empty_lustre(), asset.resource(script, bundle)], bundle)
}

fn layout(body, bundle) {
  use layout <- t.do(layout.css())
  use neo <- t.do(neo.css())
  html.doc(
    list.flatten([
      [
        html.stylesheet(asset.tailwind_2_2_11),
        asset.resource(layout, bundle),
        asset.resource(neo, bundle),
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
  |> element.to_document_string()
  |> t.done()
}

pub fn page(bundle) {
  use content <- t.do(app("website/routes/editor", "client", bundle))
  t.done(route.Page(content))
}

pub fn client() {
  let app = lustre.application(init, update, render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub type State {
  State(cache: sync.Sync, source: snippet.Snippet, display_help: Bool)
}

pub fn init(_) {
  let cache = sync.init(browser.get_origin())
  let source = editable.from_expression(expression.Vacant(""))
  let snippet = snippet.init(source, [], [], cache)
  let references = snippet.references(snippet)
  let #(cache, tasks) = sync.fetch_missing(cache, references)
  let state = State(cache, snippet, False)
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
        snippet.Conclude(_, _, _) -> #(display_help, effect.none())
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
