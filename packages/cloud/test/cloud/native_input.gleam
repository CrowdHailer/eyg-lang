import cloud/channel
import eyg/interpreter/cast
import eyg/interpreter/value as v
import overlay/check

pub fn event(event: channel.Event, expected, type_) {
  let channel.Incoming(_, _, _, value) = event
  let assert Ok(Nil) =
    check.value(value, type_, #(0, 0), fn(_) { Error("unexpected reference") })
  let assert Ok(#(tag, payload)) = cast.as_tagged(value)
  assert tag == expected
  payload
}

pub fn field(value, name) {
  let assert Ok(value) = cast.field(name, Ok, value)
  value
}

pub fn text(value, name) {
  let assert Ok(value) = cast.field(name, cast.as_string, value)
  value
}

pub fn bool(value, name) {
  field(value, name) == v.true()
}
