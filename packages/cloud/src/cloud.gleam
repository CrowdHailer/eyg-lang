import cloud/slack/api/client
import cloud/slack/channel
import cloud/system
import envoy
import gleam/erlang/process

pub fn main() -> Nil {
  let assert Ok(token) = envoy.get("SLACK_BOT_TOKEN")
  let assert Ok(_) = channel.start(client.Context(token, system.fetch))
  process.sleep_forever()
}
