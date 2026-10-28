//// Window functions that published plinth does not have.

import plinth/browser/event.{type Event}

/// Remove a listener previously registered with plinth's
/// `window.add_event_listener`.
/// Pass the same callback value that was used to register it.
@external(javascript, "./window_ffi.mjs", "removeEventListener")
pub fn remove_event_listener(
  type_: String,
  listener: fn(Event(t)) -> Nil,
) -> Nil
