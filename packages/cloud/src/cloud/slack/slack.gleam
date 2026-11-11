//// Entry module for slack channel and connection

import cloud/beam/execute
import cloud/slack/channel
import cloud/slack/client
import envoy
import eyg/hub/cache
import gleam/result
import ogre/origin

pub fn start_channel(token: String) {
  let assert Ok(hub) =
    envoy.get("EYG_ORIGIN")
    |> result.unwrap("https://eyg.run")
    |> origin.from_string_strict
  let assert Ok(identity) = client.auth_test(token)
  channel.start(
    token,
    identity.user_id,
    execute.State(origin: hub, cache: cache.ready()),
  )
}
