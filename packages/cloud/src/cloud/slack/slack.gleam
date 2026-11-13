//// Entry module for slack channel and connection

import cloud/beam/execute
import cloud/slack/channel
import cloud/slack/client
import eyg/hub/cache

pub fn start_channel(hub, token: String) {
  let assert Ok(identity) = client.auth_test(token)
  channel.start(
    token,
    identity,
    execute.State(origin: hub, cache: cache.ready()),
  )
}
