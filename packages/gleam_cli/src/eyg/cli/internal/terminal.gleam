//// Styling for terminal output, plain text when output is not a terminal or NO_COLOR is set.

import gleam/list
import javascript/mutable_reference as cell
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

pub opaque type Interrupt {
  Interrupt(pressed: cell.MutableReference(Bool), listener: fn() -> Nil)
}

pub fn interrupt() {
  let pressed = cell.new(False)
  let listener = fn() {
    let _ = cell.set(pressed, True)
    Nil
  }
  Interrupt(pressed, listener)
}

pub fn request_stop(interrupt: Interrupt) {
  interrupt.listener()
}

pub fn start_turn(interrupt: Interrupt) {
  let _ = cell.set(interrupt.pressed, False)
  case process.get() {
    Ok(host) -> {
      let _ = process.remove_signal_listener(host, "SIGINT", interrupt.listener)
      let _ = process.on_signal(host, "SIGINT", interrupt.listener)
      Nil
    }
    Error(_) -> Nil
  }
}

pub fn end_turn(interrupt: Interrupt) {
  case process.get() {
    Ok(host) -> {
      let _ = process.remove_signal_listener(host, "SIGINT", interrupt.listener)
      Nil
    }
    Error(_) -> Nil
  }
}

pub fn interrupted(interrupt: Interrupt) {
  cell.get(interrupt.pressed)
}
