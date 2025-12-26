import gleam/javascript/promise
import gleam/list
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/html
import plinth/browser/clipboard
import plinth/browser/document
import plinth/browser/event
import website/config
import website/routes/common
import website/routes/home
import website/routes/workspace/state
import website/routes/workspace/view
import website/sync/client

pub fn app(module, func) {
  use script <- asset.do(asset.bundle(module, func))
  layout([
    h.div(
      [a.id("app"), a.styles([#("position", "absolute"), #("inset", "0")])],
      [],
    ),
    h.script([a.src(asset.src(script))], ""),
  ])
}

fn layout(body) {
  use layout <- asset.do(asset.load(home.layout_path))
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
  use content <- asset.do(app("website/routes/workspace", "client"))
  asset.done(element.to_document_string(content))
}

pub fn client() {
  let app = lustre.application(do_init, do_update, view.render)
  let assert Ok(runtime) = lustre.start(app, "#app", config.load())
  document.add_event_listener("keydown", fn(e) {
    let message = lustre.dispatch(state.UserPressedCommandKey(event.key(e)))
    lustre.send(runtime, message)
  })
  Nil
}

fn do_init(config) {
  let #(state, actions) = state.init(config)
  #(state, effect.batch(list.map(actions, run)))
}

fn do_update(state, message) {
  let #(state, actions) = state.update(state, message)
  #(state, effect.batch(list.map(actions, run)))
}

fn run(action) {
  case action {
    state.FocusOnInput -> {
      echo "TODO focus on input"
      effect.none()
    }
    state.WriteToClipboard(text:) ->
      effect.from(fn(dispatch) {
        promise.map(clipboard.write_text(text), fn(result) { dispatch(todo) })
        Nil
      })
    state.ReadFromClipboard -> todo
    state.RunEffect(..) -> todo
    state.SyncAction(action) ->
      client.lustre_run_single(action, state.SyncMessage)
  }
}
