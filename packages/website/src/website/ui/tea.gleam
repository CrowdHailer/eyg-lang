//// The Elm Architecture (TEA)

import eyg/interpreter/simple_debug
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import morph/buffer

// TODO this should pass in a single cached or derived state
pub fn render(_buffer: buffer.Buffer, value, _ready_to_migrate) {
  h.div([], [
    h.p([], [element.text("App state")]),
    h.div([a.class("border-2 p-2")], [
      case value {
        Some(value) -> element.text(simple_debug.inspect(value))
        None -> element.text("has never started")
      },
    ]),
    h.p([], [element.text("Rendered app, click to send message")]),
    h.div([a.class("border-2 p-2")], [
      // case contextual.all_errors(buffer.analysis), ready_to_migrate {
    //   [], True ->
    //     h.div([event.on_click(UserClickedMigrate)], [
    //       element.text("click to upgrade"),
    //     ])
    //   [], False -> {
    //     let assert Some(value) = value
    //     case expression.call_field(mod, "render", Nil, [#(value, Nil)]) {
    //       Ok(v.String(page)) -> render_app(page)
    //       Ok(_) -> element.text("app render did not return a string")
    //       Error(_) ->
    //         element.text("app render failed, this should not happen")
    //     }
    //   }
    //   // snippet shows these
    //   type_errors, _ ->
    //     h.div(
    //       [a.class("border-2 border-orange-3 px-2")],
    //       list.map(type_errors, fn(error) {
    //         let #(_path, reason) = error
    //         h.div(
    //           [
    //             // event.on_click(state.SnippetMessage(
    //           //   state.hot_reload_key,
    //           //   snippet.UserClickedPath(path),
    //           // )),
    //           ],
    //           [element.text(debug.reason(reason))],
    //         )
    //       }),
    //     )
    // },
    ]),
  ])
}
// fn render_app(page, user_clicked_app) {
//   h.div(
//     [
//       a.attribute("dangerous-unescaped-html", page),
//       event.on_click(user_clicked_app),
//     ],
//     [],
//   )
// }
