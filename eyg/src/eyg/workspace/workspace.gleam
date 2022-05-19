import gleam/option.{Option}
import eyg/ast/editor

pub type Panel {
  Editor
  Bench
}

pub type State(n) {
  State(focus: Panel, editor: Option(editor.Editor(n)))
}
