import gleam/dynamic/decode
import gleam/json
import gleam/option.{None}
import gleam/result
import gleam/string

/// Only a leading mention addressed to this bot starts a command.
/// TODO properly parse the messages so this can work on the parsed messages
pub fn source(data: json.Json, bot_user: String) -> Result(String, Nil) {
  let decoder = {
    use text <- decode.field("text", decode.string)
    use user <- decode.field("user", decode.string)
    use bot <- decode.optional_field(
      "bot_id",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(text, user, bot))
  }
  use message <- result.try(
    json.parse(json.to_string(data), decoder) |> result.replace_error(Nil),
  )
  let #(text, user, bot) = message
  let text = string.trim_start(text)
  let mention = "<@" <> bot_user <> ">"
  case bot == None && user != bot_user && string.starts_with(text, mention) {
    False -> Error(Nil)
    True -> {
      let code =
        text |> string.drop_start(string.length(mention)) |> string.trim
      let code = case
        string.starts_with(code, "```") && string.ends_with(code, "```")
      {
        True -> {
          let code =
            code |> string.drop_start(3) |> string.drop_end(3) |> string.trim
          case string.starts_with(code, "eyg\n") {
            True -> string.drop_start(code, 4)
            False -> code
          }
        }
        False -> code
      }
      code
      |> string.replace("&lt;", "<")
      |> string.replace("&gt;", ">")
      |> string.replace("&amp;", "&")
      |> Ok
    }
  }
}
