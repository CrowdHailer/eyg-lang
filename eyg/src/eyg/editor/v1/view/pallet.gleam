// command pallet
import eyg/analysis/jm/type_ as t
import eyg/editor/v1/app.{SelectNode}
import eyg/editor/v1/view/type_
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute.{class, classes}
import lustre/element.{text}
import lustre/element/html.{div, input, span, textarea} as h
import lustre/event.{on_click}

pub fn render(state: app.WorkSpace, inferred) {
  h.form([class("cover bg-gray-100"), event.on_submit(app.Keypress("Enter"))], case
    state.mode
  {
    app.WriteLabel(value, _) -> render_label(value)
    app.WriteTerm(value, _) -> render_variable(value, inferred, state)
    app.WriteNumber(number, _) -> render_number(number)
    app.WriteText(value, _) -> render_text(value)
    _ -> render_navigate(inferred, state)
  })
}

fn render_label(value) {
  [
    input([
      class("border w-full"),
      attribute.autofocus(True),
      event.on_input(fn(v) { app.Change(v) }),
      attribute.value(value),
    ]),
  ]
}

fn render_variable(value, _inferred, _state: app.WorkSpace) {
  [
    div([], []),
    //  suggestion has been removed because there is no map of env's in the tree
    // case inferred {
    //   Some(inferred) ->
    //     case inventory.variables_at(inferred.environments, state.selection) {
    //       // using spaces because we are in pre tag and text based
    //       // not in pre tag here
    //       Ok(options) ->
    //         list.map(
    //           options,
    //           fn(option) {
    //             let #(t, term) = option
    //             span(
    //               [
    //                 class("rounded bg-blue-100 p-1"),
    //                 on_click(ClickOption(term)),
    //               ],
    //               [text(t)],
    //             )
    //           },
    //         )
    //         |> list.intersperse(text(" "))
    //       Error(_) -> [text("no env")]
    //     }
    //   None -> []
    // },
    input([
      class("border w-full"),
      attribute.autofocus(True),
      event.on_input(fn(v) { app.Change(v) }),
      attribute.value(value),
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
      attribute.value(int.to_string(number)),
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
    textarea(
      [
        attribute.rows(10),
        classes([#("w-full", True)]),
        attribute.autofocus(True),
        // on_change internally
        event.on_input(fn(v) { app.Change(v) }),
      ],
      // attribute.value(value),
      value,
    ),
  ]
}

fn render_navigate(inferred, state: app.WorkSpace) {
  [
    case inferred {
      Some(inferred) -> render_errors(inferred)
      None -> span([], [])
    },
    div([class("hstack")], [
      span([], [
        case inferred {
          Some(#(sub, _next, types)) ->
            text(
              string.append(":", {
                case dict.get(types, list.reverse(state.selection)) {
                  Ok(inferred) ->
                    case inferred {
                      Ok(t) -> {
                        let t = t.resolve(t, sub)
                        type_.render_type(t)
                      }

                      Error(#(r, t1, t2)) -> type_.render_failure(r, t1, t2)
                    }
                  Error(Nil) -> "invalid selection"
                }
              }),
            )
          None -> span([], [text("untyped")])
        },
      ]),
      span([class("expand")], []),
      span([class("text-red-500")], case state.error {
        Some(message) -> [text(message)]
        None -> []
      }),
    ]),
  ]
}

fn render_errors(inferred) {
  let #(_sub, _next, types) = inferred
  let errors =
    list.filter_map(dict.to_list(types), fn(el) {
      let #(k, v) = el
      case v {
        Ok(_) -> Error(Nil)
        Error(reason) -> Ok(#(list.reverse(k), reason))
      }
    })

  case errors != [] {
    False -> span([], [])
    True ->
      div(
        [classes([#("cover bg-red-300", True)])],
        list.map(errors, fn(err) {
          let #(path, #(reason, t1, t2)) = err
          div(
            [classes([#("cursor-pointer", True)]), on_click(SelectNode(path))],
            [text(type_.render_failure(reason, t1, t2))],
          )
        }),
      )
  }
}
