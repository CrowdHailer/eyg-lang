//// Styling for terminal output, plain text when output is not a terminal or NO_COLOR is set.

import gleam/list
import plinthx/node/process
import plinthx/node/tty

/// According to specification NO_COLOR only disables colors however it's often useful to remove all ansi codes in that case.
pub fn styled() -> Bool {
  case tty.get() {
    Ok(process) ->
      tty.is_write_tty(tty.stdout(process)) == True && !no_color(process)
    Error(Nil) -> False
  }
}

fn no_color(process) {
  case list.key_find(process.env(process), "NO_COLOR") {
    Ok("") | Error(Nil) -> False
    Ok(_) -> True
  }
}

/// Apply an ansi style function only when writing to a terminal.
pub fn style(
  styled: Bool,
  apply: fn(String) -> String,
  text: String,
) -> String {
  case styled {
    True -> apply(text)
    False -> text
  }
}
