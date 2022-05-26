import gleam/option.{None, Some}
import eyg/editor/editor.{Editor}

// TODO command mode is transform mode
pub fn is_composing(editor: Editor(_)) {
  case editor.mode {
    editor.Command -> False
    _ -> True
  }
}

// Is there a separation here between keyboard and mouse
// Actions
pub fn handle_keydown(editor, key, ctrl, input) {
  let Editor(tree: tree, typer: typer, selection: selection, mode: mode, ..) =
    editor
  let path = case selection {
    Some(path) -> path
    None -> []
  }
  // Manage without mode
  let new = case key, ctrl, input {
    "Escape", _, Some(_) -> editor.cancel(editor)
    "Enter", _, Some(text) -> editor.handle_change(editor, text)
    // TODO implement filter better but we do that under input
    _, _, Some(text) -> editor
    "q", _, None -> editor.toggle_encoded(editor)
    "Q", _, None -> editor.toggle_code(editor)
    "x", _, None -> editor.toggle_provider_expansion(editor)
    // // yd is yank delete
    "y", False, None -> editor.yank(editor)
    // TODO typecheck
    "y", True, None -> editor.paste(editor)

    _, _, None -> {
      let #(untyped, path, mode) =
        editor.handle_transformation(editor, path, key, ctrl)
      let editor = Editor(..editor, selection: Some(path), mode: mode)
      case untyped {
        None -> editor
        Some(untyped) -> editor.set_untyped(editor, untyped)
      }
    }
  }

  // crash if this doesn't work to get to handle_keydown error handling
  // if get_element in target_type always returned OK/Error we could probably work to remove the error handling
  // though is there any harm in the fall back currently in App.svelte?
  editor.target_type(new)
  new
}
