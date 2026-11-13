import cloud/session
import eyg/parser
import gleam/string

/// Fenced code is explicit, so malformed programs still get parser diagnostics.
/// Also retain the original `@bot <EYG>` shorthand for valid programs.
pub fn payload(text: String, mention: String) -> Result(session.Payload, Nil) {
  let text = string.trim(text)
  let addressed = string.starts_with(text, mention)
  let text = case addressed {
    True -> text |> string.drop_start(string.length(mention)) |> string.trim
    False -> text
  }
  case text {
    "" -> Error(Nil)
    _ -> {
      case string.starts_with(text, "```") && string.ends_with(text, "```") {
        True -> {
          let code =
            text |> string.drop_start(3) |> string.drop_end(3) |> string.trim
          let code = case string.starts_with(code, "eyg\n") {
            True -> string.drop_start(code, 4)
            False -> code
          }
          Ok(session.Code(code))
        }
        False -> {
          case addressed, parser.all_from_string(text) {
            True, Ok(_) -> Ok(session.Code(text))
            _, _ -> Ok(session.UserPrompt(text))
          }
        }
      }
    }
  }
}
