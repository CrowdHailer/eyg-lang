import gleam/io
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute.{class, style}
import lustre/element.{button, div, span, text}
import spreadsheet/log/reduce.{Frame}
import lustre/cmd

pub fn render(frame, focus) {
  let Frame(headers: headers, ..) = frame
  let width = list.length(headers)
  let grid_columns =
    string.concat(["2em repeat(", int.to_string(width), ", minmax(0, 1fr))"])
  div(
    [class("grid"), style([#("grid-template-columns", grid_columns)])],
    cells(frame, focus),
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
