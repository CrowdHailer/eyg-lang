import gleam/dynamic/decode
import gleam/string
import lustre/attribute as a
import lustre/event

pub fn on_hotkey(message: fn(String) -> t, zero: t) -> a.Attribute(t) {
  event.advanced("keydown", {
    use key <- decode.field("key", decode.string)
    use shift <- decode.optional_field("shiftKey", False, decode.bool)
    use ctrl <- decode.optional_field("ctrlKey", False, decode.bool)
    use alt <- decode.optional_field("altKey", False, decode.bool)
    use meta <- decode.optional_field("metaKey", False, decode.bool)
    let ignore = decode.failure(handled(zero), "unhandled key")
    case key {
      "Alt" | "Control" | "Shift" | "Meta" | "Tab" -> ignore
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
      | "F12" -> ignore
      _ if meta -> ignore
      // The default is not prevented so that inputs keep working.
      k if shift -> decode.success(handled(message(string.uppercase(k))))
      _ if ctrl || alt -> ignore
      k -> decode.success(handled(message(k)))
    }
  })
}

fn handled(message) {
  event.handler(
    dispatch: message,
    prevent_default: False,
    stop_propagation: True,
  )
}
