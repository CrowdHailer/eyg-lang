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
  r.run(prog, [], r.Record([]), in_cli)
  |> io.debug
  0
}

// Map composes better
fn in_cli(label, term) {
  io.debug(#("Effect", label, term))
  r.Record([])
}

external fn do_serve(fn(String) -> String, fn(String) -> Nil) -> Nil =
  "./entry.js" "serve"

fn web(_) {
  let store = javascript.make_reference(source)
  let handle = fn(x) {
    let prog = e.Apply(e.Select("web"), javascript.dereference(store))

    let a =
      inference.infer(
        map.new()
        |> map.insert(
          "string_append",
          scheme.Scheme(
            [],
            t.Fun(t.Binary, t.Open(-1), t.Fun(t.Binary, t.Open(-2), t.Binary)),
          ),
        )
        |> map.insert(
          "equal",
          scheme.Scheme(
            [],
            t.Fun(
              t.Unbound(-3),
              t.Open(-4),
              t.Fun(
                t.Unbound(-5),
                t.Open(-6),
                t.Union(t.Extend(
                  "True",
                  t.unit,
                  t.Extend("False", t.unit, t.Closed),
                )),
              ),
            ),
          ),
        ),
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

// TODO put with helpers in runtime
fn builtin2(f) {
  r.Builtin(fn(a) { r.Value(r.Builtin(fn(b) { r.Value(f(a, b)) })) })
}

const true = r.Tagged("True", r.Record([]))

const false = r.Tagged("False", r.Record([]))

fn server_run(prog, path) {
  let env = [
    #(
      "string_append",
      r.Builtin(fn(first) {
        r.Value(r.Builtin(fn(second) {
          assert r.Binary(f) = first
          assert r.Binary(s) = second
          r.Value(r.Binary(string.append(f, s)))
        }))
      }),
    ),
    #(
      "equal",
      builtin2(fn(x, y) {
        case x == y {
          True -> true
          False -> false
        }
      }),
    ),
  ]
  let request = r.Record([#("path", r.Binary(path))])
  assert return = r.run(prog, env, request, in_cli)
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
