import cloud/command
import cloud/session
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None}
import gleam/result
import gleam/string

/// Ignore bots and webhooks, including our own agent replies.
pub fn payload(
  data: json.Json,
  bot_user: String,
) -> Result(session.Payload, Nil) {
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
  case !bot && webhook == None && user != bot_user {
    False -> Error(Nil)
    True -> command.payload(text, mention)
  }
}
