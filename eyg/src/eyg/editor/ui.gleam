import eyg/ast/editor.{Editor}

// TODO command mode is transform mode
pub fn is_composing(editor: Editor(_)) {
  case editor.mode {
    editor.Command -> False
    _ -> True
  }
}
// Is there a separation here between keyboard and mouse
