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

pub fn infer(prog) {
  inference.infer(
    env(),
    prog,
    t.Unbound(-1),
    t.Open(-2),
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

pub fn env() {
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
