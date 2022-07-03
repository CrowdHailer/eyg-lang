import gleam/io
import gleam/int
import gleam/list
import lustre/attribute.{class, style}
import lustre/element.{button, div, span, text}
import spreadsheet/state.{State, Frame}
import lustre/cmd


pub fn render(state: State) {
  div(
    [
      class("grid"),
      style([#("grid-template-columns", "2em repeat(3, minmax(0, 1fr))")]),
    ],
    cells(state.frame, state.focus),
  )
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

