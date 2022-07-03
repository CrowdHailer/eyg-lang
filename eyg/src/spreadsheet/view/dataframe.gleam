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

type Cell {
  Changed(old: String, new: String)
  Unchanged(value: String)
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

  let commit = 2

  list.index_map(
    data,
    fn(i, row) {
      let double =
        list.any(
          row,
          fn(values) {
            case values {
              [#(comitted, _), ..] if comitted == commit -> True
              _ -> False
            }
          },
        )
      case double {
        False -> [
          span([class("bg-gray-50")], [text(int.to_string(i + 1))]),
          ..list.index_map(
            row,
            fn(j, values) {
              let rendered = case values {
                [] -> ""
                [#(committed, value), ..] if committed != commit ->
                  to_string(value)
                [#(_, value), ..] -> to_string(value)
              }
              let color = case x == j && y == i, int.is_even(i + j) {
                True, _ -> "bg-indigo-200"
                False, True -> "bg-blue-50"
                False, False -> ""
              }
              span([class(color)], [text(rendered)])
            },
          )
        ]
        True -> {
          let row1 = [
            span([class("bg-gray-50")], [text(int.to_string(i + 1))]),
            ..list.index_map(
              row,
              fn(j, values) {
                let #(loud, rendered) = case values {
                  [] -> #(False, "")
                  [#(committed, value), ..] if committed != commit ->
                    #(False, to_string(value))
                  [#(_, value),#(_, old), ..] -> #(True, to_string(old))
                  [#(_, value)] -> #(True, "")
                }
                let color = case x == j && y == i, loud {
                  True, _ -> "bg-indigo-200"
                  False, True -> "bg-red-100 text-red-500 line-through"
                  False, False -> ""
                }
                span([class(color)], [text(rendered)])
              },
            )
          ]
          let row2 = [
            span([class("bg-gray-50")], [text(int.to_string(i + 1))]),
            ..list.index_map(
              row,
              fn(j, values) {
                let #(loud, rendered) = case values {
                  [] -> #(False, "")
                  [#(committed, value), ..] if committed != commit ->
                    #(False, to_string(value))
                  [#(_, value), ..] -> #(True, to_string(value))
                }
                let color = case x == j && y == i,loud {
                  True, _ -> "bg-indigo-200"
                  False, True -> "bg-green-300 text-green-800"
                  False, False -> ""
                }
                span([class(color)], [text(rendered)])
              },
            )
          ]
          list.append(row1, row2)
        }
      }
    },
  )
  |> list.flatten
  |> list.append(hcells, _)
}

fn to_string(value) {
  case value {
    reduce.StringValue(value) -> value
    reduce.TableRequirements(_) -> "#TABLE"
    _ ->
      // io.debug(value)
      todo("something better with values")
  }
}
