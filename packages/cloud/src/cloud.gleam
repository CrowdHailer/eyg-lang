import cloud/slack/slack
import envoy
import gleam/erlang/process

pub fn main() -> Nil {
  let assert Ok(token) = envoy.get("SLACK_BOT_TOKEN")

  let assert Ok(_) = slack.start_channel(token)
  process.sleep_forever()
}
