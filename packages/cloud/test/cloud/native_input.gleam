import cloud/channel
import eyg/interpreter/cast
import eyg/interpreter/value as v

pub fn event(event: channel.Event, expected, _type) {
  let channel.Incoming(_, _, _, value) = event
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
