import gleam/dynamic/decode
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event

pub fn render(
  value: String,
  placeholder: String,
  handle_input: fn(String) -> a,
  handle_submit: a,
  ignore: a,
) -> element.Element(a) {
  h.div([a.class("chat-input")], [
    render_area_input(value, placeholder, handle_input, handle_submit, ignore),
    h.div([a.class("hstack split")], [
      h.div([], []),
      h.div([], [h.button([a.class("button")], [h.text("send")])]),
    ]),
  ])
}

fn render_area_input(value, placeholder, handle_input, handle_submit, ignore) {
  let on_keydown =
    event.advanced("keydown", {
      use key <- decode.field("key", decode.string)
      use shift <- decode.field("shiftKey", decode.bool)

      case key {
        "Enter" if shift ->
          decode.success(event.handler(
            dispatch: ignore,
            prevent_default: True,
            stop_propagation: False,
          ))

        "Enter" ->
          decode.success(event.handler(
            dispatch: handle_submit,
            prevent_default: True,
            stop_propagation: False,
          ))

        _ ->
          decode.success(event.handler(
            dispatch: ignore,
            prevent_default: False,
            stop_propagation: False,
          ))
      }
    })
  h.textarea(
    [
      a.placeholder(placeholder),
      event.on_input(handle_input),
      on_keydown,
    ],
    value,
  )
}
