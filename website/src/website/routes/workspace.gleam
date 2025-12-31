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
import website/harness/browser/alert
import website/harness/browser/copy
import website/harness/browser/download
import website/harness/browser/fetch
import website/harness/browser/follow
import website/harness/browser/geolocation
import website/harness/browser/now
import website/harness/browser/paste
import website/harness/browser/prompt
import website/harness/browser/random
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
      // This seems to be unnecessary if only one autofocused input, and the code doesn't have a tabindex
      effect.none()
    }
    state.WriteToClipboard(text:) ->
      effect.from(fn(dispatch) {
        promise.map(clipboard.write_text(text), fn(result) {
          dispatch(state.ClipboardWriteCompleted(result))
        })
        Nil
      })
    state.ReadFromClipboard ->
      effect.from(fn(dispatch) {
        promise.map(clipboard.read_text(), fn(result) {
          dispatch(state.ClipboardReadCompleted(result))
        })
        Nil
      })
    state.RunEffect(reference, effect) ->
      effect.from(fn(dispatch) {
        promise.map(run_effect(effect), fn(result) {
          dispatch(state.EffectImplementationCompleted(reference, result))
        })
        Nil
      })
    state.SyncAction(action) ->
      client.lustre_run_single(action, state.SyncMessage)
  }
}

fn run_effect(effect) {
  case effect {
    state.Alert(message) -> alert.run(message)
    state.Copy(text) -> copy.run(text)
    state.Download(file) -> download.run(file)
    state.Fetch(request) -> fetch.run(request)
    state.Follow(request) -> follow.run(request)
    state.Geolocation -> geolocation.run()
    state.Now -> now.run()
    state.Paste -> paste.run()
    state.Prompt(message) -> prompt.run(message)
    state.Random(max) -> random.run(max)
  }
}
