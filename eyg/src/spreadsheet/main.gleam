import gleam/io
import gleam/int
import lustre
import lustre/attribute.{autofocus}
import lustre/element.{button, div, p, text}
import lustre/event.{dispatch, on_click, on_keypress}
import lustre/cmd

external fn listen_keypress(fn(string) -> Nil) -> Nil =
  "../spreadsheet_ffi" "listenKeypress"

pub fn main() {
  let app = lustre.application(#(0, cmd.none()), update, render)
  assert Ok(dispatch) = lustre.start(app, "#app")

  listen_keypress(fn(key) {
    case key {
      "u" -> dispatch(Incr)
      _ -> dispatch(Decr)
    }
  })
}

pub type Action {
  Incr
  Decr
}

fn update(state, action) {
  case action {
    Incr -> #(state + 1, cmd.none())
    Decr -> #(state - 1, cmd.none())
  }
}

fn render(state) {
  div(
    [
      autofocus(True),
      // tabindex -1 TODO
      attribute.attribute("autoFocus", "{true}"),
      on_keypress(fn(k, a) { dispatch(Incr)(a) }),
    ],
    [
      //     button([on_click(dispatch(Decr))], [text("-")]),
      p([], [text(int.to_string(state))]),
    ],
  )
  //     button([on_click(dispatch(Incr))], [text("+")]),
  // element.input([on_keypress(fn(k, a) { dispatch(Incr)(a)})])
}
