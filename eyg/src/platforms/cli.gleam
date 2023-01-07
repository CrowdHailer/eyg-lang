import gleam/io
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import eyg/analysis/inference
import harness/stdlib
import gleam/javascript

pub fn in_cli(label, term) {
  io.debug(#("Effect", label, term))
  r.Record([])
}

pub fn run(source, _args) {
  let #(types, values) = stdlib.lib()
  let prog = e.Apply(e.Select("cli"), source)
  let inferred =
    inference.infer(
      types,
      prog,
      // TODO this needs to be in the same place as standard testing
      t.Fun(
        t.Record(t.Closed),
        t.Extend("Log", #(t.Binary, t.unit), t.Closed),
        t.Integer,
      ),
      t.Extend("Log", #(t.Binary, t.unit), t.Closed),
      javascript.make_reference(0),
      [],
    )

  case inference.sound(inferred) {
    Ok(Nil) -> {
      r.run(prog, values, r.Record([]), in_cli)
      |> io.debug
      0
    }
    Error(reasons) -> {
      io.debug("program not sound")
      io.debug(reasons)
      1
    }
  }
  // exec is run without argument, or call -> run
  // pass in args more important than exec run
}
