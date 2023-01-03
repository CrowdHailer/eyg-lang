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
  let a =
    inference.infer(
      types,
      e.Apply(prog, e.unit),
      //   TODO type properly
      t.Unbound(-1),
      t.Extend("Log", #(t.Binary, t.unit), t.Closed),
      javascript.make_reference(0),
      [],
    )

  // TODO check inference
  //   type_of(a, [])
  //   assert True = sound(a)
  // exec is run without argument, or call -> run
  // pass in args more important than exec run
  r.run(prog, values, r.Record([]), in_cli)
  |> io.debug
  0
}
