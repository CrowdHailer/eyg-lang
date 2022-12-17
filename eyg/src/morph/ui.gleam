import gleam/int
import lustre
import lustre/element.{button, div, p, text}
import lustre/event.{dispatch, on_click}
import lustre/cmd

// TODO do js(all ffi's) files need to be top level
// careful is a js not mjs file
external fn listen_keypress(fn(string) -> Nil) -> Nil =
  "../browser_ffi.js" "listenKeypress"

pub fn main() {
  let app = lustre.application(#(0, cmd.none()), update, render)
  assert Ok(dispatch) = lustre.start(app, "#app")
  listen_keypress(fn(key) {
    // Dispatch keypress i.e. just listen to event here and update should have all the logic in.
    dispatch(Keypress(key))
  })
}

pub type Action {
  Incr
  Decr
  Keypress(key: String)
}

fn update(state, action) {
  1 + 2
  case action {
    Incr -> #(state + 1, cmd.none())
    Decr -> #(state - 1, cmd.none())
    Keypress(_) -> #(state * 2, cmd.none())
  }
}

fn render(state) {
  div(
    [],
    [
      button([on_click(dispatch(Decr))], [text("-")]),
      p([], [text(int.to_string(state))]),
      button([on_click(dispatch(Incr))], [text("+")]),
    ],
  )
}
