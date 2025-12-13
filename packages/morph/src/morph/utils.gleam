import gleam/dynamic/decode
import gleam/string
import lustre/event
import plinth/browser/event as pevent

pub fn on_hotkey(message, zero) {
  event.on(
    "keydown",
    decode.new_primitive_decoder("keyboard event", fn(event) {
      let assert Ok(event) = pevent.cast_keyboard_event(event)
      let key = pevent.key(event)
      let shift = pevent.shift_key(event)
      let ctrl = pevent.ctrl_key(event)
      let alt = pevent.alt_key(event)
      case key {
        "Alt" | "Ctrl" | "Shift" | "Tab" -> Error(zero)
        "F1"
        | "F2"
        | "F3"
        | "F4"
        | "F5"
        | "F6"
        | "F7"
        | "F8"
        | "F9"
        | "F10"
        | "F11"
        | "F12" -> Error(zero)
        k if shift -> {
          // default is needed for inputs to work
          // pevent.prevent_default(event)
          pevent.stop_propagation(event)
          Ok(message(string.uppercase(k)))
        }
        _ if ctrl || alt -> Error(zero)
        k -> {
          // pevent.prevent_default(event)
          pevent.stop_propagation(event)
          Ok(message(k))
        }
      }
    }),
  )
}
