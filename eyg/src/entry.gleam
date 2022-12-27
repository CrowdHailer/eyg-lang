import gleam/io
import gleam/list
import gleam/map
import gleam/option.{None}
import gleam/result
import gleam/javascript
import gleam/javascript/array.{Array}
import eyg/analysis/inference
import eyg/analysis/unification
import eyg/analysis/typ as t
import eyg/runtime/interpreter
import eygir/expression as e
import source.{source}

// document that rad start shell at dollar
// This becomes the entry point
external fn args(Int) -> Array(String) =
  "" "process.argv.slice"

// main iszero arity

pub fn main(args) {
  case args {
    // TODO could have test
    ["cli", ..rest] -> cli(rest)
    ["web", ..rest] -> web(rest)
  }
}

pub fn resolve(inf: inference.Infered, typ) {
  unification.resolve(inf.substitutions, typ)
}

fn type_of(inf: inference.Infered, path) {
  let r = case map.get(inf.paths, path) {
    Ok(r) -> r
    Error(Nil) -> todo("invalid path")
  }
  case r {
    Ok(t) -> Ok(unification.resolve(inf.substitutions, t))
    Error(reason) -> Error(reason)
  }
}

fn sound(inf: inference.Infered) {
  list.all(map.values(inf.paths), fn(typed) { result.is_ok(typed) })
}

// Probably create an analysis state
// TODO in error handle unification todo
// TODO handle error in rewrite row
fn cli(_) {
  let prog = e.Apply(e.Select("cli"), source)
  let a =
    inference.infer(
      map.new(),
      e.Apply(prog, e.unit),
      t.Unbound(-1),
      t.Extend("Log", #(t.Binary, t.unit), t.Closed),
      javascript.make_reference(0),
      [],
    )
  type_of(a, [])
  assert True = sound(a)

  let exec = interpreter.eval(prog, [], fn(x) { x })
  // |> io.debug
  run(exec, interpreter.Record([]))
  |> io.debug
  0
}

fn run(prog, term) {
  case interpreter.eval_call(prog, term, fn(x) { x }) {
    // interpreter.Effect("Log", interpreter.Binary(b)) -> {
    //   io.debug(b)
    //   run(interpreter.Builtin(k), interpreter.Record([]))
    // }
    interpreter.Effect(_, _) -> todo("unhandled effect")
    term -> term
  }
}

external fn do_serve(fn(String) -> String) -> Nil =
  "./entry.js" "serve"

fn web(_) {
  do_serve(fn(x) {
    let prog = e.Apply(e.Select("web"), source)

    let a =
      inference.infer(
        map.new(),
        prog,
        t.Unbound(-1),
        t.Closed,
        javascript.make_reference(0),
        [],
      )
    type_of(a, [])
    |> io.debug()
    // TODO does this return type matter for anything
    let handler = interpreter.eval(prog, [], fn(x) { x })
    // TODO use get field function
    // TODO need a run function that takes effect handlers, do we need to pass id as cont here
    assert interpreter.Record([#("body", interpreter.Binary(body)), ..]) =
      interpreter.eval_call(handler, interpreter.Binary(x), fn(x) { x })
      |> io.debug
    body
  })

  0
}
