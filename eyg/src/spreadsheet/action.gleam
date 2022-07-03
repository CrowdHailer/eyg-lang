
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
  case key {
    "ArrowRight" -> {
      let State(frame, #(x, y)) = state
      State(frame,#(int.min(x + 1, list.length(frame.headers) - 1), y))
    }
    "ArrowLeft" -> {
      let State(frame, #(x, y)) = state
      State(frame, #(int.max(x - 1, 0), y))
    }
    "ArrowUp" -> {
      let State(frame, #(x, y)) = state
      State(frame, #(x, int.max(y - 1, 0)))
    }
    "ArrowDown" -> {
      let State(frame, #(x, y)) = state
      State(frame,#(x, int.min(y + 1, list.length(frame.data) - 1)))
    }

    _ -> {
      io.debug(key)
      state
    }
  }
}