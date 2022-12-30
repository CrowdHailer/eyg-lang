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
external fn read_file_sync(String, String) -> String =
  "fs" "readFileSync"

// TODO remove source in Gleam format page
pub fn cli(_) {
  let json = read_file_sync("saved/saved.json", "utf8")
  assert Ok(source) = decode.from_json(json)
  let prog = e.Apply(e.Select("cli"), source)
  let a =
    inference.infer(
      env(),
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
  r.run(prog, env_values(), r.Record([]), in_cli)
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

fn env() {
  map.new()
  |> map.insert(
    "string_append",
    scheme.Scheme(
      [t.Effect(-1), t.Effect(-2)],
      t.Fun(t.Binary, t.Open(-1), t.Fun(t.Binary, t.Open(-2), t.Binary)),
    ),
  )
  |> map.insert(
    "equal",
    scheme.Scheme(
      [],
      // TODO needs term and variable
      // [-3, -4, -5, -6],
      t.Fun(
        t.Unbound(-3),
        t.Open(-4),
        t.Fun(
          t.Unbound(-5),
          t.Open(-6),
          t.Union(t.Extend("True", t.unit, t.Extend("False", t.unit, t.Closed))),
        ),
      ),
    ),
  )
  |> map.insert(
    "list_fold",
    scheme.Scheme(
      [],
      // TODO
      // [-7, -8, -9, -10, -11, -12, -13],
      t.Fun(
        t.LinkedList(t.Unbound(-7)),
        t.Open(-8),
        t.Fun(
          t.Unbound(-9),
          t.Open(-10),
          t.Fun(
            t.Fun(
              t.Unbound(-7),
              t.Open(-11),
              t.Fun(t.Unbound(-9), t.Open(-12), t.Unbound(-9)),
            ),
            t.Open(-13),
            t.Unbound(-9),
          ),
        ),
      ),
    ),
  )
  |> map.insert(
    "string_concat",
    scheme.Scheme([], t.Fun(t.LinkedList(t.Binary), t.Open(-14), t.Binary)),
  )
  |> map.insert(
    "add",
    scheme.Scheme(
      [],
      t.Fun(t.Integer, t.Open(-15), t.Fun(t.Integer, t.Open(-15), t.Integer)),
    ),
  )
}

pub fn env_values() {
  [
    #(
      "string_append",
      r.Builtin(fn(first, k) {
        r.continue(
          k,
          r.Builtin(fn(second, k) {
            assert r.Binary(f) = first
            assert r.Binary(s) = second
            r.continue(k, r.Binary(string.append(f, s)))
          }),
        )
      }),
    ),
    #(
      "equal",
      builtin2(fn(x, y, k) {
        case x == y {
          True -> true
          False -> false
        }
        |> r.continue(k, _)
      }),
    ),
    #(
      "list_fold",
      builtin3(fn(list, initial, f, k) {
        assert r.LinkedList(elements) = list
        do_fold(elements, initial, f, k)
      }),
    ),
    #(
      "string_concat",
      r.Builtin(fn(list, k) {
        assert r.LinkedList(elements) = list
        r.continue(
          k,
          r.Binary(list.fold(
            elements,
            "",
            fn(buffer, e) {
              assert r.Binary(value) = e
              string.append(buffer, value)
            },
          )),
        )
      }),
    ),
    #(
      "add",
      builtin2(fn(x, y, k) {
        assert r.Integer(x) = x
        assert r.Integer(y) = y
        r.continue(k, r.Integer(x + y))
      }),
    ),
  ]
}

fn do_fold(elements, state, f, k) {
  case elements {
    [] -> r.continue(k, state)
    [e, ..rest] ->
      r.eval_call(f, e, r.eval_call(_, state, do_fold(rest, _, f, k)))
  }
}

fn web(_) {
  let store = javascript.make_reference(source)
  let handle = fn(x) {
    let prog = e.Apply(e.Select("web"), javascript.dereference(store))

    let a =
      inference.infer(
        env(),
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
  r.Builtin(fn(a, k) { r.continue(k, r.Builtin(fn(b, k) { f(a, b, k) })) })
}

fn builtin3(f) {
  r.Builtin(fn(a, k) {
    r.continue(
      k,
      r.Builtin(fn(b, k) {
        r.continue(k, r.Builtin(fn(c, k) { f(a, b, c, k) }))
      }),
    )
  })
}

const true = r.Tagged("True", r.Record([]))

const false = r.Tagged("False", r.Record([]))

fn server_run(prog, path) {
  let request = r.Record([#("path", r.Binary(path))])
  assert return = r.run(prog, env_values(), request, in_cli)
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
