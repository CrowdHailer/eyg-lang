import gleam/io
import gleam/list
import plinth/nodejs
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import eyg/analysis/inference
import harness/stdlib
import harness/effect
import gleam/javascript/promise.{Promise}

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
  |> effect.extend("HTTP", effect.http())
  |> effect.extend("Await", effect.await())
  |> effect.extend("Wait", effect.wait())
}

pub fn typ() {
  t.Fun(t.LinkedList(t.Binary), handlers().0, t.Integer)
}

pub fn run(source, args) {
  let #(types, _values) = stdlib.lib()
  let prog = e.Apply(e.Select("cli"), source)
  let hrstart = nodejs.start()

  use code <- // let inferred = inference.infer(types, prog, typ(), t.Closed)
  // let hrend = nodejs.duration(hrstart)
  // io.debug(#("inference", hrend))
  // console.info("Inference time (hr): %ds %dms", hrend)
  promise.await(case Ok(Nil) {
    Ok(Nil) -> {
      let hrstart = nodejs.start()
      use ret <- promise.map(r.run_async(
        prog,
        stdlib.env(),
        r.LinkedList(list.map(args, r.Binary)),
        handlers().1,
      ))

      io.debug(ret)
      let assert Ok(r.Integer(return)) = ret
      let hrend = nodejs.duration(hrstart)
      io.debug(#("run", hrend))
      return
    }
    Error(reasons) -> {
      io.debug("program not sound")
      io.debug(reasons)
      promise.resolve(1)
    }
  })
  code
  |> nodejs.exit()
  promise.resolve(code)
}
