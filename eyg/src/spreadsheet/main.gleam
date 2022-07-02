import gleam/io
import gleam/int
import lustre
import lustre/element.{button, div, p, text}
import lustre/event.{dispatch, on_click}
import lustre/cmd

pub fn main() {
  let app = lustre.application(#(0, cmd.none()), update, render)
  lustre.start(app, "#app")
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
    [],
    [
      button([on_click(dispatch(Decr))], [text("-")]),
      p([], [text(int.to_string(state))]),
      button([on_click(dispatch(Incr))], [text("+")]),
    ],
  )
}
