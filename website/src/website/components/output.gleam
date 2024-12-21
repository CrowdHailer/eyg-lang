// This could move closer to morph and other views but only if it stays generic enough
import eyg/runtime/value as v
import gleam/list
import lustre/attribute as a
import lustre/element.{text}
import lustre/element/html as h

pub fn render(value) {
  case value {
    v.LinkedList(items) -> {
      let headers = all_fields(items)
      case headers {
        [] -> render_value(value)
        _ -> {
          let rows = list.map(items, row_content(headers, _))
          table(headers, rows)
        }
      }
    }
    v.Str(string) -> h.pre([], [text(string)])
    _ -> render_value(value)
  }
}

fn render_value(value) {
  text(v.debug(value))
}

pub fn table(headings, values) {
  h.table([], [
    h.thead(
      [a.class("bg-gray-200")],
      list.map(headings, fn(h) { h.th([a.class("px-2")], [text(h)]) }),
    ),
    h.tbody([], list.map(values, row)),
  ])
}

fn row(values) {
  h.tr([], list.map(values, cell))
}

fn cell(value) {
  h.td([a.class("border text-right px-2")], [text(value)])
}

fn all_fields(items) {
  list.fold(items, [], fn(acc, item) {
    case item {
      v.Record(fields) ->
        list.fold(fields, acc, fn(acc, field) {
          let #(key, _) = field
          case list.contains(acc, key) {
            True -> acc
            False -> [key, ..acc]
          }
        })
      _ -> acc
    }
  })
  |> list.reverse
}

fn row_content(headers, value) {
  case value {
    v.Record(fields) -> {
      list.map(headers, fn(header) {
        case list.key_find(fields, header) {
          Ok(value) -> v.debug(value)
          Error(Nil) -> "-"
        }
      })
    }
    _ -> list.map(headers, fn(_) { "-" })
  }
}
