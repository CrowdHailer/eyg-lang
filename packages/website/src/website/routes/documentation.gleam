import gleam/javascript/promise
import gleam/list
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/html
import plinth/browser/document
import plinth/browser/event as browser_event
import website/config
import website/harness/browser
import website/routes/common
import website/routes/documentation/state
import website/routes/documentation/view
import website/routes/home

pub fn app(module, func) {
  use script <- asset.do(asset.bundle(module, func))
  layout([html.empty_lustre(), h.script([a.src(asset.src(script))], "")])
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
  use content <- asset.do(app("website/routes/documentation", "client"))
  asset.done(element.to_document_string(content))
}

pub fn client() {
  let app = lustre.application(do_init, do_update, view.render)
  let assert Ok(runtime) = lustre.start(app, "#app", config.load())
  document.add_event_listener("keydown", fn(e) {
    let message = lustre.dispatch(state.UserPressedKey(browser_event.key(e)))
    lustre.send(runtime, message)
  })
  Nil
}

fn do_init(config) {
  let #(state, actions) = state.init(config)
  #(state, effect.batch(list.map(actions, effect)))
}

fn do_update(state, message) {
  let #(state, actions) = state.update(state, message)
  #(state, effect.batch(list.map(actions, effect)))
}

fn effect(action) {
  effect.from(fn(dispatch) {
    promise.map(browser.run(action), dispatch)
    Nil
  })
}
