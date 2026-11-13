//// Narrow an Event to KeyboardEvent using the native DOM constructor.

import plinth/browser/event.{type Event, type KeyboardEvent, type UIEvent}

@external(javascript, "./event_ffi.mjs", "keyboardEvent")
pub fn keyboard_event(
  event: Event(a),
) -> Result(Event(UIEvent(KeyboardEvent)), Nil)
