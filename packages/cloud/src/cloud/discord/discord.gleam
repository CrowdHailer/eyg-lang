//// Entry module for the Discord channel and connection.

import cloud/beam/execute
import cloud/discord/channel
import cloud/discord/client
import eyg/hub/cache
import ogre/origin

pub fn start_channel(hub: origin.Origin, token: String, guild: String) {
  let assert Ok(identity) = client.current_user(token)
  let assert Ok(guild) = client.guild(token, guild)
  channel.start(
    token,
    guild,
    identity.id,
    execute.State(origin: hub, cache: cache.ready()),
  )
}
