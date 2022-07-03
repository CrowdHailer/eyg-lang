import gleam/io
import gleam/int
import gleam/list
import lustre/cmd
import spreadsheet/state.{State}

pub type Action {
  Keypress(String)
}

pub fn update(state, action) {
  case action {
    Keypress(key) -> #(handle_keypress(state, key), cmd.none())
  }
}

fn handle_keypress(state, key) {
  // let width = list.length(frame.headers)
  // TODO
  // list.length(frame.data)
  let width = 3
  let height = 2
  case key {
    "ArrowRight" -> {
      let State(frame, #(t, x, y)) = state
      State(frame, #(t, int.min(x + 1, width - 1), y))
    }
    "ArrowLeft" -> {
      let State(frame, #(t, x, y)) = state
      State(frame, #(t, int.max(x - 1, 0), y))
    }
    "ArrowUp" -> {
      let State(frame, #(t, x, y)) = state
      State(frame, #(t, x, int.max(y - 1, 0)))
    }
    "ArrowDown" -> {
      let State(frame, #(t, x, y)) = state
      State(frame, #(t, x, int.min(y + 1, height - 1)))
    }
    "Enter" -> {
      let State(frame, #(t, x, y)) = state
      State(frame, #(4, x, y))
    }

    _ -> {
      io.debug(key)
      state
    }
  }
}
