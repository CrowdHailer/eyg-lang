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

  // exec is run without argument, or call -> run
  // pass in args more important than exec run
  interpreter.run(prog, interpreter.Record([]), in_cli)
  |> io.debug
  0
}

// Map composes better
fn in_cli(label, term) {
  io.debug(#("Effect", label, term))
  interpreter.Record([])
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
    // TODO use get field function
    assert interpreter.Record([#("body", interpreter.Binary(body)), ..]) =
      interpreter.run(prog, interpreter.Binary(x), in_cli)
      |> io.debug
    body
  })

  // TODO does this return type matter for anything
  0
}
