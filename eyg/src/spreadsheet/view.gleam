import gleam/int
import gleam/string
import lustre/attribute.{class, style}
import lustre/element.{button, div, span, text}
import spreadsheet/state
import spreadsheet/view/dataframe

pub fn render(state: state.State) {
  let #(_, x, y) = state.focus
  let #(name, frame) = state.frame(state)
  let pre = case state.diff {
    True -> "DIFF"
    False -> "VIEW"
  }
  let at = case state.offset {
    0 -> "" 
    n -> string.concat(["@ -", int.to_string(n)])
  }
  let command =
    string.concat([
      pre,
      at,
      " ",
      name,
      " ",
      "(",
      int.to_string(x),
      " ",
      int.to_string(y),
      ")",
    ])
  div(
    [class("flex flex-col min-h-screen")],
    [
      dataframe.render(frame, #(x, y), state.diff),
      div([class("mt-auto p-1 bg-gray-900 text-white")], [text(command)]),
    ],
  )
}
