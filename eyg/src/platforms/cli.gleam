import gleam/io
import gleam/list
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

pub const typ = t.Fun(
  t.LinkedList(t.Binary),
  t.Extend("Log", #(t.Binary, t.Record(t.Closed)), t.Closed),
  t.Integer,
)

// t.Unit doesn't work here
external fn exit(Int) -> Nil =
  "" "process.exit"

pub fn run(source, args) {
  let #(types, values) = stdlib.lib()
  let prog = e.Apply(e.Select("cli"), source)
  let inferred =
    inference.infer(
      types,
      prog,
      typ,
      t.Extend("Log", #(t.Binary, t.unit), t.Closed),
    )

  case inference.sound(inferred) {
    Ok(Nil) -> {
      assert r.Integer(return) =
        r.run(prog, values, r.LinkedList(list.map(args, r.Binary)), in_cli)
        |> io.debug
      return
    }
    Error(reasons) -> {
      io.debug("program not sound")
      io.debug(reasons)
      1
    }
  }
  |> exit()
  // exec is run without argument, or call -> run
  // pass in args more important than exec run
}
