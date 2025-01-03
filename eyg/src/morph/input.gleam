import gleam/int
import lustre/attribute as a
import lustre/element/html as h
import lustre/event

pub fn render_text(value) {
  input(value, "text")
}

pub fn render_number(value) {
  let raw = case value {
    0 -> ""
    _ -> int.to_string(value)
  }
  input(raw, "number")
}

pub fn styled_input(value, type_, class) {
  h.form([event.on_submit(Submit)], [
    h.input([
      a.class(class),
      a.value(value),
      a.type_(type_),
      a.attribute("autofocus", "true"),
      // Don't require as text/number can be ""/0
      // a.required(required),
      // Id like to listen to the reset event but it doesn't seem to get fired from any keyboard interaction.
      // I've tested with listening to reset on input and form. and including a reset button explicitly.
      event.on_keydown(KeyDown),
      event.on_input(UpdateInput),
    ]),
  ])
}

fn input(value, type_) {
  let class =
    "block w-full bg-transparent border-l-8 border-gray-700 focus:border-gray-300 p-1 outline-none"
  styled_input(value, type_, class)
}

pub type Message {
  Submit
  KeyDown(String)
  UpdateInput(String)
}

pub type Next(t) {
  Confirmed(t)
  Cancelled
  Continue(t)
}

pub fn update_text(old, message) {
  case message {
    Submit -> Confirmed(old)
    KeyDown("Escape") -> Cancelled
    KeyDown(_) -> Continue(old)
    UpdateInput(new) -> Continue(new)
  }
}

pub fn update_number(old, message) {
  case message {
    Submit -> Confirmed(old)
    KeyDown("Escape") -> Cancelled
    KeyDown(_) -> Continue(old)
    UpdateInput(new) ->
      case int.parse(new) {
        Ok(new) -> Continue(new)
        Error(Nil) -> Continue(old)
      }
  }
}
