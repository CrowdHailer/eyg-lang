import gleam/io
import gleam/list
import gleam/map
import gleam/option.{None, Some}
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/analysis/inference
import eyg/analysis/typ as t
import gleam/result

pub fn binary(value) {
  e.Apply(e.Tag("Binary"), e.Binary(value))
}

pub fn integer(value) {
  e.Apply(e.Tag("Integer"), e.Integer(value))
}

pub fn variable(label) {
  e.Apply(e.Tag("Variable"), e.Binary(label))
}

// TODO decide func fun lambda, use constants for keys
pub fn lambda(param, body) {
  e.Apply(
    e.Tag("Lambda"),
    e.Apply(
      e.Apply(e.Extend("label"), e.Binary(param)),
      e.Apply(e.Apply(e.Extend("body"), body), e.Empty),
    ),
  )
}

// TODO test below
fn id(x) {
  r.Value(x)
}

fn step(path, i) {
  list.append(path, [i])
}

// TODO deduplicate fn
fn field(row: t.Row(a), label) {
  case row {
    t.Open(_) | t.Closed -> Error(Nil)
    t.Extend(l, t, _) if l == label -> Ok(t)
    t.Extend(_, _, tail) -> field(tail, label)
  }
}

const r_unit = r.Record([])

pub fn type_to_language_term(type_) {
  case type_ {
    t.Unbound(i) -> r.Tagged("Unbound", r.Integer(i))
    t.Integer -> r.Tagged("Integer", r_unit)
    t.Binary -> r.Tagged("Binary", r_unit)
    t.LinkedList(item) -> r.Tagged("List", type_to_language_term(item))
    t.Fun(from, effects, to) -> {
      let from = type_to_language_term(from)
      let to = type_to_language_term(to)
      r.Tagged("Lambda", r.Record([#("from", from), #("to", to)]))
    }
    t.Record(row) -> r.Tagged("Record", row_to_language_term(row))
    t.Union(row) -> r.Tagged("Union", row_to_language_term(row))
  }
}

fn row_to_language_term(row) {
  todo("row_to_language_term")
}

pub fn language_term_to_expression(term) -> e.Expression {
  assert r.Tagged(node, inner) = term
  case node {
    "Variable" -> {
      assert r.Binary(value) = inner
      e.Variable(value)
    }
    "Lambda" -> {
      assert r.Record(fields) = inner
      assert Ok(r.Binary(param)) = list.key_find(fields, "label")
      assert Ok(body) = list.key_find(fields, "body")
      e.Lambda(param, language_term_to_expression(body))
    }
    "Binary" -> {
      assert r.Binary(value) = inner
      e.Binary(value)
    }
    "Integer" -> {
      assert r.Integer(value) = inner
      e.Integer(value)
    }
  }
}

pub fn expand(generator, inferred, path) {
  try fit =
    inference.type_of(inferred, path)
    |> result.map_error(fn(_) { todo("this inf error") })
  try needed = case fit {
    t.Union(row) ->
      // TODO ordered fields fn
      field(row, "Ok")
      |> result.map_error(fn(_) { "no Ok field" })

    _ -> Error("not a union")
  }

  io.debug(#("needed", needed))
  assert r.Value(g) = r.eval(generator, [], id)
  assert r.Value(result) = r.eval_call(g, type_to_language_term(needed), id)

  assert r.Tagged(tag, value) = result
  case tag {
    "Ok" -> {
      let generated = language_term_to_expression(value)
      io.debug(#("generated", generated))
      let inferred = inference.infer(map.new(), generated, needed, t.Closed)
      io.debug(inference.sound(inferred))
      let code = case inference.sound(inferred) {
        Ok(Nil) -> e.Apply(e.Tag("Ok"), generated)
        Error(_) -> e.Apply(e.Tag("Error"), e.unit)
      }
      Ok(code)
    }
  }
}
