//// Optional level-one adapter: one shell invocation of the EYG executable.

import gleam/dynamic.{type Dynamic}
import gleam/string
import pi_extension/native as n

pub fn allowed(command: String) {
  let command = string.trim(command)
  let prefix =
    command == "eyg"
    || string.starts_with(command, "eyg ")
    || string.starts_with(command, "eyg\t")
  prefix && scan(string.to_graphemes(command), False)
}

fn scan(letters, quoted) {
  case letters {
    [] -> !quoted
    ["'", ..rest] -> scan(rest, !quoted)
    [letter, ..rest] ->
      case quoted {
        True -> scan(rest, quoted)
        False -> !string.contains(";&|`$<>\n\r\\", letter) && scan(rest, quoted)
      }
  }
}

pub fn main(pi: Dynamic) {
  let _ =
    n.call(pi, "on", [
      n.data("tool_call"),
      n.data(fn(event) {
        case
          n.string(event, "toolName") == "bash"
          && !allowed(n.string(n.field(event, "input"), "command"))
        {
          False -> n.data(Nil)
          True ->
            n.object([
              #("block", n.data(True)),
              #(
                "reason",
                n.data(
                  "Only the eyg command can be run; use eyg run -c '<code>'.",
                ),
              ),
            ])
        }
      }),
    ])
  Nil
}
