import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/interpreter/simple_debug
import eyg/ir/tree as ir
import gleam/int
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
import website/components/snippet
import website/components/vertical_menu
import website/config
import website/harness/harness
import website/routes/common
import website/routes/editor/state
import website/routes/editor/view
import website/routes/home
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
  use content <- asset.do(app("website/routes/editor", "client"))
  asset.done(element.to_document_string(content))
}

pub fn client() {
  let app = lustre.application(do_init, do_update, view.render)
  let assert Ok(_) = lustre.start(app, "#app", config.load())
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
  todo
  // case action {
  //   SyncAction(action) -> client.lustre_run([action], SyncMessage)
  //   DoToggleFullScreen ->
  //     effect.from(fn(_d) {
  //       let w = window.self()
  //       let doc = window.document(w)
  //       case document.fullscreen_element(doc) {
  //         Ok(_) -> document.exit_fullscreen(doc)
  //         Error(Nil) -> {
  //           let assert Ok(el) = document.get_element_by_id("app")
  //           pelement.request_fullscreen(el)
  //         }
  //       }
  //       Nil
  //     })
  //   FocusOnBuffer -> dispatch_nothing(snippet.focus_on_buffer)
  //   FocusOnInput -> dispatch_nothing(snippet.focus_on_input)
  //   ReadFromClipboard -> dispatch_to_snippet(snippet.read_from_clipboard())
  //   ReadShellFromClipboard -> dispatch_to_shell(shell.read_from_clipboard())
  //   RunExternalHandler(id:, thunk:) ->
  //     dispatch_to_shell(
  //       promise.map(thunk(), fn(reply) {
  //         shell.RunnerMessage(runner.HandlerCompleted(id, reply))
  //       }),
  //     )
  //   WriteToClipboad(text:) ->
  //     dispatch_to_snippet(snippet.write_to_clipboard(text))
  // }
}
