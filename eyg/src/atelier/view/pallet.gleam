// command pallet
import gleam/io
import gleam/dynamic
import gleam/list
import gleam/map
import gleam/string
import gleam/option.{None, Some}
import lustre/element.{div, input, span, text, textarea}
import lustre/event.{on_click}
import lustre/attribute.{class, classes}
import eyg/analysis/inference
import eyg/incremental/cursor
import eyg/analysis/jm/error
import eyg/analysis/jm/type_ as t
import atelier/app.{ClickOption, SelectNode}
import atelier/view/type_
import atelier/inventory

pub fn render(state: app.WorkSpace) {
  div(
    [class("cover bg-gray-100")],
    case state.mode {
      app.WriteLabel(value, _) -> render_label(value)
      app.WriteTerm(value, _) -> render_variable(value, state)
      app.WriteNumber(number, _) -> render_number(number)
      app.WriteText(value, _) -> render_text(value)
      _ -> render_navigate(state)
    },
  )
}

fn render_label(value) {
  [
    input([
      class("border w-full"),
      attribute.autofocus(True),
      event.on_input(fn(v) { app.Change(v) }),
      attribute.value(dynamic.from(value)),
    ]),
  ]
}

fn render_variable(value, state: app.WorkSpace) {
  [
    div([], []),
    // case inferred {
    //   Some(inferred) ->
    //     // TODO use inferred but we dont have the whole env map.
    //     []
    //     // case inventory.variables_at(inferred.environments, state.selection) {
    //     //   // using spaces because we are in pre tag and text based
    //     //   // not in pre tag here
    //     //   Ok(options) ->
    //     //     list.map(
    //     //       options,
    //     //       fn(option) {
    //     //         let #(t, term) = option
    //     //         span(
    //     //           [
    //     //             class("rounded bg-blue-100 p-1"),
    //     //             on_click(ClickOption(term)),
    //     //           ],
    //     //           [text(t)],
    //     //         )
    //     //       },
    //     //     )
    //     //     |> list.intersperse(text(" "))
    //     //   Error(_) -> [text("no env")]
    //     // }
    //   None -> []
    // },
    input([
      class("border w-full"),
      attribute.autofocus(True),
      event.on_input(fn(v) { app.Change(v) }),
      attribute.value(dynamic.from(value)),
    ]),
  ]
}

fn render_number(number) {
  [
    input([
      class("border w-full"),
      attribute.type_("number"),
      attribute.autofocus(True),
      event.on_input(fn(v) { app.Change(v) }),
      attribute.value(dynamic.from(number)),
    ]),
  ]
}

// Do text areas have change event
fn render_text(value) {
  [
    div(
      [
        classes([
          #("bg-green-500", True),
          #("text-white", True),
          #("cursor-pointer", True),
        ]),
        on_click(app.Commit),
      ],
      [text("Done")],
    ),
    textarea([
      attribute.rows(10),
      classes([#("w-full", True)]),
      attribute.autofocus(True),
      event.on_input(fn(v) { app.Change(v) }),
      attribute.value(dynamic.from(value)),
    ]),
  ]
}

fn render_navigate(state: app.WorkSpace) {
  let #(sub, _next, types) = state.inferred
  [
    case types {
      Some(types) -> render_errors(types)
      None -> span([], [])
    },
    div(
      [class("hstack")],
      [
        span(
          [],
          [
            case types {
              Some(types) ->
                text(string.append(
                  ":",
                  {
                    let assert Ok(c) =
                      cursor.at(state.selection, state.root, state.source)
                    let id = cursor.inner(c)
                    let assert Ok(type_) = map.get(types, id)
                    case type_ {
                      Ok(type_) -> type_.render_type(t.resolve(type_, sub))
                      Error(#(reason, t1, t2)) ->
                        type_.render_failure(
                          reason,
                          t.resolve(t1, sub),
                          t.resolve(t2, sub),
                        )
                    }
                  },
                ))
              None -> span([], [text("type checking")])
            },
          ],
        ),
        span([class("expand")], []),
        span(
          [class("text-red-500")],
          case state.error {
            Some(message) -> [text(message)]
            None -> []
          },
        ),
      ],
    ),
  ]
}

fn render_errors(types) {
  let errors =
    list.filter_map(
      map.to_list(types),
      fn(el) {
        let #(k, v) = el
        case v {
          Ok(_) -> Error(Nil)
          Error(reason) -> Ok(#(k, reason))
        }
      },
    )

  case list.length(errors) != 0 {
    False -> span([], [])
    True ->
      div(
        [classes([#("cover bg-red-300", True)])],
        list.map(
          errors,
          fn(err) {
            let #(path, reason) = err
            // TODO real path
            let path = []
            div(
              [classes([#("cursor-pointer", True)]), on_click(SelectNode(path))],
              [text(render_failure(reason))],
            )
          },
        ),
      )
  }
}

pub fn render_failure(reason) {
  let #(reason, _, _) = reason
  case reason {
    error.RecursiveType -> "recursive type"
    _ -> "other error"
  }
}
