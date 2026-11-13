import cloud/command
import cloud/session
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None}
import gleam/result
import gleam/string

/// New human messages are either direct code or an agent prompt.
pub fn payload(
  data: json.Json,
  bot_user: String,
) -> Result(session.Payload, Nil) {
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
  case bot == None && user != bot_user {
    False -> Error(Nil)
    True -> {
      text
      |> string.replace("&lt;", "<")
      |> string.replace("&gt;", ">")
      |> string.replace("&amp;", "&")
      |> command.payload("<@" <> bot_user <> ">")
    }
  }
}
