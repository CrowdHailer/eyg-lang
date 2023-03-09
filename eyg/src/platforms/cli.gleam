import gleam/io
import gleam/list
import gleam/map
import gleam/nodejs
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

external fn start() -> #(Int, Int) =
  "process" "hrtime"

external fn duration(#(Int, Int)) -> #(Int, Int) =
  "process" "hrtime"

pub fn run(source, args) {
  let #(types, values) = stdlib.lib()
  let prog = e.Apply(e.Select("cli"), source)
  let hrstart = start()
  let inferred = inference.infer(types, prog, typ(), t.Closed)
  let hrend = duration(hrstart)
  io.debug(#("inference", hrend))

  // console.info("Inference time (hr): %ds %dms", hrend)
  case inference.sound(inferred) {
    Ok(Nil) -> {
      let hrstart = start()
      let assert Ok(r.Integer(return)) =
        r.run(
          prog,
          r.Env([], map.new()),
          r.LinkedList(list.map(args, r.Binary)),
          handlers().1,
        )
        |> io.debug
      let hrend = duration(hrstart)
      io.debug(#("run", hrend))
      return
    }
    Error(reasons) -> {
      io.debug("program not sound")
      io.debug(reasons)
      1
    }
  }
  |> nodejs.exit()
}
