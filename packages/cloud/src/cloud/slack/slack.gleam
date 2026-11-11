//// Entry module for slack channel and connection

import cloud/slack/channel
import cloud/slack/client

pub fn start_channel(token: String) {
  let assert Ok(identity) = client.auth_test(token)
  channel.start(token, identity.user_id)
}
