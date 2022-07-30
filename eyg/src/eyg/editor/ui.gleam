import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/javascript/array
import eyg/editor/editor.{Editor}

// TODO command mode is transform mode
pub fn is_composing(editor: Editor) {
  case editor.mode {
    editor.Command -> False
    _ -> True
  }
}

pub fn choices(editor: Editor) {
  case editor.mode {
    editor.Select(choices, filter) ->
      list.filter(choices, string.starts_with(_, filter))
    _ -> []
  }
  |> array.from_list
}

fn ui_warn(key, ctrl) {
  io.debug(string.concat(["unable to handle command ", key, ""]))
}

// There is a duplication of state where mode swiches to draft and the cursor is within a text box
// Is there a separation here between keyboard and mouse
// Actions
pub fn handle_keydown(editor, key, ctrl, input) {
  let result = case key, ctrl, input {
    "Escape", _, Some(_) -> Ok(editor.cancel(editor))
    "Enter", _, Some(text) -> Ok(editor.handle_change(editor, text))
    " ", _, Some(text) -> Ok(editor.autofill_choice(editor, text))
    _, _, Some(text) -> Ok(editor)
    // Command mode
    // toggle_dump
    // toggle_generated source -> code for computers encoded could be the code view
    "q", _, None -> Ok(editor.toggle_encoded(editor))
    "Q", _, None -> Ok(editor.toggle_code(editor))
    "y", False, None -> Ok(editor.yank(editor))
    "y", True, None -> editor.paste(editor)
    "a", _, None -> editor.increase_selection(editor)
    "s", _, None -> editor.decrease_selection(editor)
    "x", _, None -> Ok(editor.toggle_provider_expansion(editor))
    _, _, None -> {
      let Editor(selection: selection, mode: mode, ..) = editor
      let path = case selection {
        Some(path) -> path
        None -> []
      }
      let #(untyped, path, mode) =
        editor.handle_transformation(editor, path, key, ctrl)
      let editor = Editor(..editor, selection: Some(path), mode: mode)
      Ok(case untyped {
        None -> editor
        Some(untyped) -> editor.set_untyped(editor, untyped)
      })
    }
  }
  case result {
    Ok(editor) -> editor
    // TODO equality check here
    Error(Nil) -> {
      ui_warn(key, ctrl)
      editor
    }
  }
}

pub fn handle_input(editor: Editor, data) {
  case editor.mode {
    editor.Select(choices, _filter) -> {
      let mode = editor.Select(choices, data)
      Editor(..editor, mode: mode)
    }
    _ -> editor
  }
}

fn rest_to_path(rest) {
  case rest {
    "" -> Ok([])
    _ ->
      // empty string makes unparsable as int list
      string.split(rest, ",")
      |> list.try_map(int.parse)
  }
}

// At the editor level we might want to handle semantic events like select node. And have display do handle click
pub fn handle_click(editor: Editor, target) {
  case string.split(target, ":") {
    ["root"] -> Editor(..editor, selection: Some([]), mode: editor.Command)
    ["p", rest] -> {
      assert Ok(path) = rest_to_path(rest)
      Editor(..editor, selection: Some(path), mode: editor.Command)
    }
    [choice] -> editor.handle_change(editor, choice)
  }
}
