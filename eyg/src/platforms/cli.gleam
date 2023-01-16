import gleam/io
import gleam/list
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import eyg/analysis/inference
import harness/stdlib
import harness/effect

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
}

pub fn typ() {
  t.Fun(t.LinkedList(t.Binary), handlers().0, t.Integer)
}

// t.Unit doesn't work here
external fn exit(Int) -> Nil =
  "" "process.exit"

pub fn run(source, args) {
  let #(types, values) = stdlib.lib()
  let prog = e.Apply(e.Select("cli"), source)
  let inferred = inference.infer(types, prog, typ(), t.Closed)

  case inference.sound(inferred) {
    Ok(Nil) -> {
      assert Ok(r.Integer(return)) =
        r.run(
          prog,
          values,
          r.LinkedList(list.map(args, r.Binary)),
          handlers().1,
        )
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
