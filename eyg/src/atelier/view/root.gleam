import gleam/dynamic
import gleam/io
import gleam/option.{None, Some}
import lustre/element.{button, div, input, p, pre, span, text}
import lustre/event.{dispatch, on_click, on_keydown}
import lustre/attribute.{class}
import atelier/app
import atelier/view/projection

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

  div(
    [class("h-screen vstack")],
    [
      div([class("spacer")], []),
      projection.render(state.source, state.selection),
      div([class("spacer")], []),
      case input_value {
        Some(value) ->
          input([
            class("border w-full"),
            attribute.autofocus(True),
            event.on_input(fn(v, d) { dispatch(app.Change(v))(d) }),
            attribute.value(dynamic.from(value)),
          ])
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
              span([], [text("morph")]),
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
