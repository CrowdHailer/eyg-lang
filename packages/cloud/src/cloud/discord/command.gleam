import gleam/dynamic/decode
import gleam/json
import gleam/option.{None}
import gleam/result
import gleam/string

/// Only a leading mention addressed to this bot starts a command.
pub fn source(data: json.Json, bot_user: String) -> Result(String, Nil) {
  let author_decoder = {
    use id <- decode.field("id", decode.string)
    use bot <- decode.optional_field("bot", False, decode.bool)
    decode.success(#(id, bot))
  }
  let decoder = {
    use text <- decode.field("content", decode.string)
    use author <- decode.field("author", author_decoder)
    use webhook <- decode.optional_field(
      "webhook_id",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(text, author, webhook))
  }
  use message <- result.try(
    json.parse(json.to_string(data), decoder) |> result.replace_error(Nil),
  )
  let #(text, #(user, bot), webhook) = message
  let text = string.trim_start(text)
  let mention = case string.starts_with(text, "<@!" <> bot_user <> ">") {
    True -> "<@!" <> bot_user <> ">"
    False -> "<@" <> bot_user <> ">"
  }
  case
    !bot
    && webhook == None
    && user != bot_user
    && string.starts_with(text, mention)
  {
    False -> Error(Nil)
    True -> {
      let code =
        text |> string.drop_start(string.length(mention)) |> string.trim
      case string.starts_with(code, "```") && string.ends_with(code, "```") {
        False -> Ok(code)
        True -> {
          let code =
            code |> string.drop_start(3) |> string.drop_end(3) |> string.trim
          case string.starts_with(code, "eyg\n") {
            True -> Ok(string.drop_start(code, 4))
            False -> Ok(code)
          }
        }
      }
    }
  }
}
