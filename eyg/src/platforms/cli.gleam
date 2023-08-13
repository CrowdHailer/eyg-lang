import gleam/io
import gleam/list
import eygir/expression as e
import eygir/decode
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/stdlib
import harness/effect
import gleam/javascript/promise
import plinth/javascript/big_int
import plinth/node/fs
import plinth/node/process
import harness/ffi/cast
import harness/ffi/core
import harness/ffi/env

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
  |> effect.extend("HTTP", effect.http())
  |> effect.extend("Await", effect.await())
  |> effect.extend("Wait", effect.wait())
  |> effect.extend("File_Write", file_write())
  |> effect.extend("Read_Source", read_source())
}

pub fn typ() {
  t.Fun(t.LinkedList(t.Binary), handlers().0, t.Integer)
}

pub fn run(source, args) {
  // let #(types, _values) = stdlib.lib()
  let prog = e.Apply(e.Select("cli"), source)
  // let hrstart = nodejs.start()

  use code <- // let inferred = inference.infer(types, prog, typ(), t.Closed)
  // let hrend = nodejs.duration(hrstart)
  // io.debug(#("inference", hrend))
  // console.info("Inference time (hr): %ds %dms", hrend)
  promise.await(case Ok(Nil) {
    Ok(Nil) -> {
      let hrstart = process.hrtime()
      use ret <- promise.map(r.run_async(
        prog,
        stdlib.env(),
        r.LinkedList(list.map(args, r.Binary)),
        handlers().1,
      ))

      io.debug(ret)
      let assert Ok(r.Integer(return)) = ret
      let hrend = process.hrtime()
      io.debug(#("run", big_int.subtract(hrend, hrstart)))
      return
    }
    Error(reasons) -> {
      io.debug("program not sound")
      io.debug(reasons)
      promise.resolve(1)
    }
  })
  code
  |> process.exit()
  promise.resolve(code)
}

fn file_write() {
  #(
    t.Binary,
    t.unit,
    fn(request, k) {
      let env = env.empty()
      let rev = []
      use file <- cast.require(
        cast.field("file", cast.string, request),
        rev,
        env,
        k,
      )
      use content <- cast.require(
        cast.field("content", cast.string, request),
        rev,
        env,
        k,
      )
      io.debug(file)
      fs.write_file_sync(file, content)
      |> io.debug
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

// Don't need the detail of decoding JSON in EYG as will move away from it.
fn read_source() {
  #(
    t.Binary,
    t.result(t.Binary, t.unit),
    fn(file, k) {
      let env = env.empty()
      let rev = []

      use file <- cast.require(cast.string(file), rev, env, k)
      let json = fs.read_file_sync(file)
      case decode.from_json(json) {
        Ok(exp) ->
          r.prim(
            r.Value(r.LinkedList(core.expression_to_language(exp))),
            rev,
            env,
            k,
          )
        Error(_) -> r.prim(r.Value(r.unit), rev, env, k)
      }
    },
  )
}
