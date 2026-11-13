//// Conversation addresses and shared operations for platform plugins.
////
//// Each plugin publishes its native input type and emits EYG values of that type.
//// The configured channel handler decides which session and policy-backed work to run.

import cloud/data
import eyg/analysis/type_/binding
import gleam/option.{type Option}

/// Where a message lives and where a response goes back to.
/// `channel` is the platform's channel id, a direct message is also a channel.
/// `thread` is the id of the root message when the message is in a thread.
pub type Conversation {
  Conversation(platform: String, channel: String, thread: Option(String))
}

/// A plugin-owned value routed to a channel; its shape is not normalised.
pub type Event {
  Incoming(conversation: Conversation, value: data.Value)
}

/// Operations a plugin performs on its platform.
pub type Outbound {
  Outbound(
    /// The native EYG input accepted by this implementation's handlers.
    input_type: binding.Mono,
    /// Post text to a conversation, a thread conversation posts a reply in the thread.
    /// Returns the id of the new message.
    post: fn(Conversation, String) -> Result(String, String),
    /// The human readable name of a channel, used to configure the channel.
    channel_name: fn(String) -> String,
    /// The id and name of every channel the cloud can post in,
    /// used to send the events of other connections to a channel by name.
    channels: fn() -> Result(List(#(String, String)), String),
  )
}

/// The channel id with the thread, used as a key for one conversation.
pub fn key(conversation: Conversation) -> String {
  let Conversation(platform:, channel:, thread:) = conversation
  let base = platform <> ":" <> channel
  case thread {
    option.Some(thread) -> base <> ":" <> thread
    option.None -> base
  }
}
