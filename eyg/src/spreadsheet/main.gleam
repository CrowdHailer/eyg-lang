import gleam/io
import gleam/int
import gleam/list
import lustre
import lustre/attribute.{class, style}
import lustre/element.{button, div, span, text}
import lustre/event.{dispatch, on_click, on_keypress}
import lustre/cmd

external fn listen_keypress(fn(string) -> Nil) -> Nil =
  "../spreadsheet_ffi" "listenKeypress"

pub fn main() {
  let app = lustre.application(#(init(), cmd.none()), update, render)
  assert Ok(dispatch) = lustre.start(app, "#app")

  listen_keypress(fn(key) {
    // Dispatch keypress i.e. just listen to event here and update should have all the logic in.
    dispatch(Keypress(key))
  })
}

pub type State {
  State(frame: Frame, focus: #(Int, Int))
}

fn init() {
  State(
    Frame(
      ["Name", "Address", "Stuff"],
      [["Alice", "London", ""], ["Bob", "London", ""]],
    ),
    #(0, 0),
  )
}

pub type Action {
  Keypress(String)
}

fn update(state, action) {
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

// Database as a Gleam file of [Commit([EAV(...), EAV(...)])]

fn render(state) {
  dataframe(state)
}

pub type Frame {
  Frame(headers: List(String), data: List(List(String)))
}

fn cells(frame, focus) {
  let #(x, y) = focus
  let Frame(headers, data) = frame
  let hcells =
    list.map(
      headers,
      fn(h) { span([class("bg-gray-900 text-white")], [text(h)]) },
    )
  let hcells = [span([class("bg-gray-900")], []), ..hcells]

  list.index_map(
    data,
    fn(i, row) {
      [
        span([class("bg-gray-50")], [text(int.to_string(i + 1))]),
        ..list.index_map(
          row,
          fn(j, value) {
            let color = case x == j && y == i, int.is_even(i + j) {
              True, _ -> "bg-indigo-300"
              False, True -> "bg-blue-50"
              False, False -> ""
            }
            span([class(color)], [text(value)])
          },
        )
      ]
    },
  )
  |> list.flatten
  |> list.append(hcells, _)
}

fn dataframe(state: State) {
  div(
    [
      class("grid"),
      style([#("grid-template-columns", "2em repeat(3, minmax(0, 1fr))")]),
    ],
    cells(state.frame, state.focus),
  )
}
