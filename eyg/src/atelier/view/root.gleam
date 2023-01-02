import gleam/dynamic
import gleam/string
import gleam/io
import gleam/list
import gleam/map
import gleam/result
import gleam/option.{None, Some}
import lustre/element.{button, div, input, p, pre, span, text}
import lustre/event.{dispatch, on_click, on_keydown}
import lustre/attribute.{class}
import atelier/app
import atelier/view/projection
import atelier/view/typ
import eyg/runtime/standard

// TODO add to gleam
fn do_filter_errors(l, acc) {
  case l {
    [] -> list.reverse(acc)
    [Ok(_), ..rest] -> do_filter_errors(rest, acc)
    [Error(reason), ..rest] -> do_filter_errors(rest, [reason, ..acc])
  }
}

pub fn filter_errors(l) {
  do_filter_errors(l, [])
}

// maybe belongs in procejection .render
pub fn render(state: app.WorkSpace) {
  let input_value = case state.mode {
    app.WriteLabel(value, _) -> Some(value)
    _ -> None
  }
  let input_number = case state.mode {
    app.WriteNumber(number, _) -> Some(number)
    _ -> None
  }

  let inferred = standard.infer(state.source)
  map.filter(inferred.paths, fn(k, v) { result.is_error(v) })

  // TODO print errors
  div(
    [class("h-screen vstack")],
    [
      div([class("spacer")], []),
      projection.render(state.source, state.selection, inferred),
      div([class("spacer")], []),
      case input_value {
        Some(value) ->
          div(
            [class("w-full")],
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
                        // TODO on click needs to make the selection
                        span([class("rounded bg-blue-100 p-1")], [text(v)])
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
            ],
          )
        None -> div([], [])
      },
      case input_number {
        Some(number) ->
          input([
            class("border w-full"),
            attribute.type_("number"),
            attribute.autofocus(True),
            event.on_input(fn(v, d) { dispatch(app.Change(v))(d) }),
            attribute.value(dynamic.from(number)),
          ])
        None -> div([], [])
      },
      div(
        [class("cover bg-gray-100")],
        [
          div(
            [class("hstack")],
            [
              span(
                [],
                [
                  text(string.append(
                    ":",
                    inferred
                    |> standard.type_of(state.selection)
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
        ],
      ),
    ],
  )
}
