//// A message that is a direct invocation of an EYG script.
////
//// Messages that consist of a single code block tagged `eyg` are run with the channel shell.
//// Every other message is for the channel's agent.

import gleam/string

pub fn parse(text: String) -> Result(String, Nil) {
  let text = string.trim(text)
  case string.starts_with(text, "```eyg"), string.ends_with(text, "```") {
    True, True -> {
      let code = text |> string.drop_start(6) |> string.drop_end(3)
      case string.contains(code, "```") {
        True -> Error(Nil)
        False -> Ok(string.trim(code))
      }
    }
    _, _ -> Error(Nil)
  }
}
