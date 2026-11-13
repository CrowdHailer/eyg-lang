//// Executable example from the Gleam embedding guide.

import eyg/embed/run
import eyg/interpreter/value as v
import eyg/parser
import gleam/io

pub fn main() {
  let assert Ok(source) =
    parser.all_from_string(
      "let _ = perform Log(\"Hello, host\") !int_add(40, 2)",
    )
  let handle = fn(messages, label, lift) {
    case label, lift {
      "Log", v.String(message) -> Ok(#([message, ..messages], v.unit()))
      _, _ -> Error("unsupported host operation")
    }
  }
  let #(messages, answer) =
    run.expression(source, [], [], handle, run.no_references)
  assert messages == ["Hello, host"]
  assert answer == Ok(v.Integer(42))
  io.println("PASS host collected one Log and returned 42")
}
