// command pallet
import gleam/dynamic
import gleam/list
import gleam/map
import gleam/string
import gleam/option.{None, Some}
import lustre/element.{button, div, input, p, pre, span, text, textarea}
import lustre/event.{dispatch, on_click, on_keydown}
import lustre/attribute.{class, classes}
import eyg/analysis/inference
import atelier/app.{ClickOption, SelectNode}
import atelier/view/typ

pub fn render(state: app.WorkSpace, inferred) {
  div(
    [class("cover bg-gray-100")],
    case state.mode {
      app.WriteLabel(value, _) -> render_label(value, inferred, state)
      app.WriteNumber(number, _) -> render_number(number)
      app.WriteText(value, _) -> render_text(value)
      _ -> render_navigate(inferred, state)
    },
  )
}

fn render_label(value, inferred: inference.Infered, state) {
  [
    div(
      [],
      case map.get(inferred.environments, state.selection) {
        // using spaces because we are in pre tag and text based
        // not in pre tag here
        Ok(env) ->
          list.map(
            map.keys(env)
            |> list.unique,
            fn(v) {
              span(
                [
                  class("rounded bg-blue-100 p-1"),
                  on_click(dispatch(ClickOption(v))),
                ],
                [text(v)],
              )
            },
          )
          |> list.intersperse(text(" "))
        Error(_) -> [text("no env")]
      },
    ),
    input([
      class("border w-full"),
      attribute.autofocus(True),
      event.on_input(fn(v, d) { dispatch(app.Change(v))(d) }),
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
      event.on_input(fn(v, d) { dispatch(app.Change(v))(d) }),
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
        on_click(dispatch(app.Commit)),
      ],
      [text("Done")],
    ),
    textarea([attribute.rows(10), classes([#("w-full", True)])]),
  ]
}

fn render_navigate(inferred: inference.Infered, state) {
  [
    render_errors(inferred),
    div(
      [class("hstack")],
      [
        span(
          [],
          [
            text(string.append(
              ":",
              inferred
              |> inference.type_of(state.selection)
              |> typ.render(),
            )),
          ],
        ),
        span([class("spacer")], []),
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

fn render_errors(inferred: inference.Infered) {
  let errors =
    list.filter_map(
      map.to_list(inferred.types),
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
            div(
              [
                classes([#("cursor-pointer", True)]),
                on_click(dispatch(SelectNode(path))),
              ],
              [text(typ.render_failure(reason))],
            )
          },
        ),
      )
  }
}
