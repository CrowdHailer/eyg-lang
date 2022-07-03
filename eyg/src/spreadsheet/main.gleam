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
  let app = lustre.application(#(0, cmd.none()), update, render)
  assert Ok(dispatch) = lustre.start(app, "#app")

  listen_keypress(fn(key) {
    // Dispatch keypress i.e. just listen to event here and update should have all the logic in.
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

// Database as a Gleam file of [Commit([EAV(...), EAV(...)])]

fn render(state) {
  dataframe(state)
}

type Frame {
  Frame(headers: List(String), data: List(List(String)))
}

fn cells(frame) {
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
            let color = case int.is_even(i + j) {
              True -> "bg-blue-50"
              False -> ""
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

fn f() {
  Frame(
    ["Name", "Address", "Stuff"],
    [["Alice", "London", ""], ["Bob", "London", ""]],
  )
}

fn dataframe(state) {
  div(
    [
      class("grid"),
      style([#("grid-template-columns", "2em repeat(3, minmax(0, 1fr))")]),
    ],
    cells(f()),
  )
}
