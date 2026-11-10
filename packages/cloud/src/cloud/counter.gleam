import gleam/int
import howdy/ui
import howdy/ui/button.{Primary, Secondary}
import lustre
import lustre/element.{text}
import lustre/event

pub type Msg {
  Increment
  Decrement
}

pub fn app() {
  lustre.simple(init, update, view)
}

fn init(start: Int) -> Int {
  start
}

fn update(count: Int, msg: Msg) -> Int {
  case msg {
    Increment -> count + 1
    Decrement -> count - 1
  }
}

fn view(count: Int) {
  ui.card([], [
    ui.h2("Counter"),
    ui.p([text(int.to_string(count))]),
    ui.row([], [
      ui.button(Secondary, [event.on_click(Decrement)], [text("-")]),
      ui.button(Primary, [event.on_click(Increment)], [text("+")]),
    ]),
  ])
}
