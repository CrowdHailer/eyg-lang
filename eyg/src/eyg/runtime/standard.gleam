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
import harness/stdlib

pub fn infer(prog) {
  inference.infer(
    stdlib.lib().0,
    prog,
    t.Record(t.Extend(
      "cli",
      t.Fun(t.Record(t.Closed), t.Open(-1000), t.Unbound(-1001)),
      t.Extend(
        "web",
        t.Fun(
          t.Record(t.Extend("path", t.Binary, t.Closed)),
          t.Open(-1002),
          t.Record(t.Extend("body", t.Binary, t.Closed)),
        ),
        t.Open(-1003),
      ),
    )),
    t.Open(-1004),
    javascript.make_reference(0),
    [],
  )
}

pub fn type_of(inf: inference.Infered, path) {
  let r = case map.get(inf.paths, path) {
    Ok(r) -> r
    Error(Nil) -> {
      io.debug(path)
      todo("invalid path")
    }
  }
  case r {
    Ok(t) -> Ok(unification.resolve(inf.substitutions, t))
    Error(reason) -> Error(reason)
  }
}

fn env() {
  map.new()
  // TODO effects are matching and we need them all open here. Potentially
  // unification should be ok on closed open
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
}

fn env_values() {
  [
    #(
      "list_fold",
      builtin3(fn(list, initial, f, k) {
        assert r.LinkedList(elements) = list
        do_fold(elements, initial, f, k)
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
