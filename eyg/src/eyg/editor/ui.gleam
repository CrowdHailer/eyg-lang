import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/javascript/array
import eyg/editor/editor.{Editor}

// TODO command mode is transform mode
pub fn is_composing(editor: Editor(_)) {
  case editor.mode {
    editor.Command -> False
    _ -> True
  }
}

pub fn choices(editor: Editor(_)) {
  case editor.mode {
    editor.Select(choices, filter) ->
      list.filter(choices, string.starts_with(_, filter))
    _ -> []
  }
  |> array.from_list
}

// Is there a separation here between keyboard and mouse
// Actions
pub fn handle_keydown(editor, key, ctrl, input) {
  case key, ctrl, input {
    "Escape", _, Some(_) -> editor.cancel(editor)
    "Enter", _, Some(text) -> editor.handle_change(editor, text)
    " ", _, Some(text) -> editor.autofill_choice(editor, text)
    _, _, Some(text) -> editor
    // Command mode
    "q", _, None -> editor.toggle_encoded(editor)
    "Q", _, None -> editor.toggle_code(editor)
    "x", _, None -> editor.toggle_provider_expansion(editor)
    "y", False, None -> editor.yank(editor)
    // TODO typecheck
    "y", True, None -> editor.paste(editor)

    _, _, None -> {
      let Editor(tree: tree, typer: typer, selection: selection, mode: mode, ..) =
        editor
      let path = case selection {
        Some(path) -> path
        None -> []
      }
      let #(untyped, path, mode) =
        editor.handle_transformation(editor, path, key, ctrl)
      let editor = Editor(..editor, selection: Some(path), mode: mode)
      case untyped {
        None -> editor
        Some(untyped) -> editor.set_untyped(editor, untyped)
      }
    }
  }
}

pub fn handle_input(editor: Editor(_), data) {
  case editor.mode {
    editor.Select(choices, _filter) -> {
      let mode = editor.Select(choices, data)
      Editor(..editor, mode: mode)
    }
    _ -> editor
  }
}
