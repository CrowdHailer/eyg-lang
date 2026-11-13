//// Native plugin events and outbound operations. Session identity is separate.
////
//// Each plugin publishes its native input type and emits EYG values of that type.
//// The configured channel handler decides which session and policy-backed work to run.

import cloud/data
import eyg/analysis/type_/binding
import gleam/option.{type Option}
import gleam/string

/// A plugin-owned value routed to a channel; its shape is not normalised.
/// `reply` is the native reply destination, never a session identifier.
pub type Event {
  Incoming(
    platform: String,
    channel: String,
    reply: Option(String),
    value: data.Value,
  )
}

/// Operations a plugin performs on its platform.
pub type Outbound {
  Outbound(
    /// The native EYG input accepted by this implementation's handlers.
    input_type: binding.Mono,
    /// The plugin interprets the channel and optional reply destination.
    /// Returns the id of the new message.
    post: fn(String, Option(String), String) -> Result(String, String),
    /// The human readable name of a channel, used to configure the channel.
    channel_name: fn(String) -> String,
    /// The id and name of every channel the cloud can post in,
    /// used to send the events of other connections to a channel by name.
    channels: fn() -> Result(List(#(String, String)), String),
  )
}

pub fn installation(platform: String, id: String) -> String {
  platform <> "/" <> id
}

pub fn platform(address: String) -> String {
  case string.split(address, "/") {
    [platform, ..] -> platform
    _ -> address
  }
}

pub fn at(event: Event, installation: String) -> Event {
  Incoming(..event, platform: installation)
}
