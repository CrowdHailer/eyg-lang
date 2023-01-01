import gleam/io
import gleam/list
import gleam/map
import gleam/option.{None}
import gleam/result
import gleam/string
import gleam/javascript
import gleam/javascript/array.{Array}
import eyg/analysis/inference
import eyg/analysis/unification
import eyg/analysis/scheme
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import eyg/runtime/standard
import eygir/expression as e
import eygir/decode
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
external fn read_file_sync(String, String) -> String =
  "fs" "readFileSync"

// TODO remove source in Gleam format page
pub fn cli(_) {
  let json = read_file_sync("saved/saved.json", "utf8")
  assert Ok(source) = decode.from_json(json)
  let prog = e.Apply(e.Select("cli"), source)
  let a =
    inference.infer(
      standard.env(),
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
  r.run(prog, standard.env_values(), r.Record([]), in_cli)
  |> io.debug
  0
}

// Map composes better
pub fn in_cli(label, term) {
  io.debug(#("Effect", label, term))
  r.Record([])
}

external fn do_serve(fn(String) -> String, fn(String) -> Nil) -> Nil =
  "./entry.js" "serve"

// env should be the same, i.e. stdlib because env stuff argument to the run fn

fn web(_) {
  let store = javascript.make_reference(source)
  let handle = fn(x) {
    let prog = e.Apply(e.Select("web"), javascript.dereference(store))

    let a =
      inference.infer(
        standard.env(),
        prog,
        t.Unbound(-1),
        t.Closed,
        javascript.make_reference(0),
        [],
      )
    type_of(a, [])
    |> io.debug()
    server_run(prog, x)
  }

  let save = fn(raw) {
    assert Ok(source) = decode.from_json(raw)
    javascript.set_reference(store, source)
    write_file_sync("saved/saved.json", raw)
    Nil
  }
  do_serve(handle, save)
  // TODO use get field function
  // TODO does this return type matter for anything
  0
}

external fn write_file_sync(String, String) -> Nil =
  "fs" "writeFileSync"

fn server_run(prog, path) {
  let request = r.Record([#("path", r.Binary(path))])
  assert return = r.run(prog, standard.env_values(), request, in_cli)
  assert r.Binary(body) = field(return, "body")
  body
}

// TODO linux with list as an effect

// move to runtime or interpreter
fn field(term, field) {
  case term {
    r.Record(fields) ->
      case list.key_find(fields, field) {
        Ok(value) -> value
        Error(Nil) -> todo("no field")
      }
    _ -> todo("not a record")
  }
}
