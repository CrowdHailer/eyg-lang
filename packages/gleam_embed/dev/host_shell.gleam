//// A person and an agent can share this same typed shell and host state.

import eyg/analysis/type_/isomorphic as t
import eyg/embed/shell
import eyg/interpreter/value as v
import gleam/io
import gleam/option.{None, Some}

fn handle(total, label, lift) {
  case label, lift {
    "Add", v.Integer(n) -> Ok(#(total + n, v.Integer(total + n)))
    _, _ -> Error("unsupported operation")
  }
}

pub fn main() {
  let session = shell.new([#("Add", #(t.Integer, t.Integer))])
  let code = "let n = perform Add(5)\nlet id = (x) -> { x }"
  io.println("> " <> code)
  let shell.Run(shell: session, state: total, outcome:) =
    shell.run(session, code, 0, handle)
  assert total == 5
  assert outcome == shell.Returned(None)
  io.println(shell.report([], outcome))

  let code = "!int_add(id(n), 1)"
  io.println("> " <> code)
  let shell.Run(shell: session, state: total, outcome:) =
    shell.run(session, code, total, handle)
  assert total == 5
  assert outcome == shell.Returned(Some(v.Integer(6)))
  io.println(shell.report([], outcome))

  let code = "let _ = perform Add(1)\nperform Launch({})"
  io.println("> " <> code)
  let shell.Run(shell: session, state: total, outcome:) =
    shell.run(session, code, total, handle)
  assert total == 5
  let assert shell.TypeFailed(_) = outcome
  io.println(shell.report([], outcome))

  let code = "id(\"still here\")"
  io.println("> " <> code)
  let shell.Run(state: total, outcome:, ..) =
    shell.run(session, code, total, handle)
  assert total == 5
  assert outcome == shell.Returned(Some(v.String("still here")))
  io.println(shell.report([], outcome))
  io.println("PASS retained bindings, polymorphism and checking before effects")
}
