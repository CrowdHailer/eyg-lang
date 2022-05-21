import gleam/dynamic
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/javascript/array.{Array}
import eyg/ast/editor

pub type Panel {
  Editor
  Bench
}

pub type State(n) {
  State(focus: Panel, editor: Option(editor.Editor(n)))
}

// Bench rename panel benches?
pub type Mount {
  Static(value: String)
  String2String
  TestSuite(result: String)
  UI
}


// CLI
// ScanCycle
// TODO add inspect to std lib
external fn inspect_gleam(a) -> String =
  "../../gleam" "inspect"

external fn inspect(a) -> String =
  "" "JSON.stringify"

pub fn mounts(state: State(n)) {
  case state.editor {
    None -> []

    Some(editor) ->
      case editor.eval(editor) {
        Ok(code) ->
          [
            case dynamic.field("test", dynamic.string)(code) {
              Ok(test) -> [TestSuite(test)]
              Error(_) -> []
            },
            case dynamic.field("spreadsheet", Ok)(code) {
              Ok(test) -> [UI]
              Error(_) -> []
            },
            [Static(inspect(code))],
          ]
          |> list.flatten
        _ -> []
      }
  }
  |> array.from_list()
}
