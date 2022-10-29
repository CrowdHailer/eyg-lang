import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer/monotype as t
import eyg/typer
import eyg/analysis/shake.{shake}

pub fn literal_test() {
  let source = e.binary("")
  assert t.Record([], _) = shake(source, t.Tuple([]))

  let source = e.tuple_([])
  assert t.Record([], _) = shake(source, t.Tuple([]))
  let source = e.hole()
  assert t.Record([], _) = shake(source, t.Tuple([]))
}

pub fn variable_test() {
  let source = e.variable("a")
  assert t.Record([#("a", t.Tuple([]))], _) = shake(source, t.Tuple([]))
  //   assert t.Record([#("a", t.Tuple([]))], _) = shake(source, t.Binary)
}

pub fn tuple_test() {
  let source = e.tuple_([e.variable("a"), e.variable("b")])
  assert t.Record([#("a", _), #("b", _)], _) = shake(source, t.Tuple([]))

  let source = e.tuple_([e.variable("a"), e.variable("a")])
  assert t.Record([#("a", _)], _) = shake(source, t.Tuple([]))

  let source =
    e.tuple_([
      e.access(e.variable("a"), "foo"),
      e.access(e.variable("a"), "bar"),
    ])
  assert t.Record([#("a", inner)], _) = shake(source, t.Tuple([]))
  assert t.Record([#("foo", _), #("bar", _)], _) = inner

  let source = e.tuple_([e.variable("a"), e.access(e.variable("a"), "foo")])
  assert t.Record([#("a", inner)], _) = shake(source, t.Tuple([]))
  assert t.Record([#("foo", _)], _) = inner
}

pub fn record_test() {
  let source = e.record([#("foo", e.variable("a")), #("bar", e.variable("b"))])
  assert t.Record([#("a", _), #("b", _)], _) = shake(source, t.Tuple([]))

  let source = e.record([#("foo", e.variable("a")), #("bar", e.variable("a"))])
  assert t.Record([#("a", _)], _) = shake(source, t.Tuple([]))

  let source =
    e.record([
      #("foo", e.variable("a")),
      #("bar", e.access(e.variable("a"), "ping")),
    ])
  assert t.Record([#("a", t.Record([#("ping", _)], _))], _) =
    shake(source, t.Tuple([]))
}

pub fn tagged_test() {
  let source = e.tagged("Foo", e.variable("a"))
  assert t.Record([#("a", _)], _) = shake(source, t.Tuple([]))

  let source = e.tagged("Foo", e.access(e.variable("a"), "foo"))
  assert t.Record([#("a", t.Record([#("foo", _)], _))], _) =
    shake(source, t.Tuple([]))
}

pub fn function_call_test() {
  let source = e.call(e.variable("a"), e.variable("b"))
  assert t.Record([#("a", _), #("b", _)], _) = shake(source, t.Tuple([]))

  let source = e.call(e.variable("id"), e.variable("id"))
  assert t.Record([#("id", _)], _) = shake(source, t.Tuple([]))
}

pub fn assignment_test() {
  let source = e.let_(p.Tuple([]), e.variable("a"), e.variable("b"))
  assert t.Record([#("a", _), #("b", _)], _) = shake(source, t.Tuple([]))

  let source = e.let_(p.Tuple([]), e.variable("a"), e.variable("a"))
  assert t.Record([#("a", _)], _) = shake(source, t.Tuple([]))
}

pub fn variable_shadowing_test() {
  let source = e.let_(p.Variable("a"), e.tuple_([]), e.variable("a"))
  assert t.Record([], _) = shake(source, t.Tuple([]))

  let source =
    e.let_(
      p.Tuple(["a", "b"]),
      e.variable("b"),
      e.tuple_([e.variable("a"), e.variable("c")]),
    )
  assert t.Record([#("b", _), #("c", _)], _) = shake(source, t.Tuple([]))
}

pub fn function_test() {
  let source = e.function(p.Tuple([]), e.variable("a"))
  assert t.Record([#("a", _)], _) = shake(source, t.Tuple([]))

  // Pass through expected
  let source = e.function(p.Tuple([]), e.variable("a"))
  assert t.Record([#("a", t.Record([#("foo", _)], _))], _) =
    shake(source, t.Record([#("foo", t.Tuple([]))], None))
}

pub fn let_function_test() {
  let source =
    e.let_(
      p.Variable("f"),
      e.function(p.Tuple([]), e.variable("a")),
      e.variable("f"),
    )
  assert t.Record([#("a", _)], _) = shake(source, t.Tuple([]))
}

pub fn recursive_function_test() {
  let source =
    e.let_(
      p.Variable("loop"),
      e.function(p.Variable(""), e.call(e.variable("loop"), e.tuple_([]))),
      e.variable("loop"),
    )
  assert t.Record([], _) = shake(source, t.Tuple([]))
}

pub fn parameter_shadowing_test() {
  let source =
    e.function(
      p.Tuple(["a", "b"]),
      e.tuple_([e.variable("a"), e.variable("c")]),
    )
  assert t.Record([#("c", _)], _) = shake(source, t.Tuple([]))
}

pub fn access_test() {
  let source = e.access(e.access(e.variable("a"), "foo"), "bar")
  assert t.Record(
    [#("a", t.Record([#("foo", t.Record([#("bar", _)], _))], _))],
    _,
  ) = shake(source, t.Tuple([]))
}

pub fn case_test() {
  let source =
    e.case_(e.variable("a"), [#("Foo", p.Variable(""), e.variable("b"))])
  assert t.Record([#("a", _), #("b", _)], _) = shake(source, t.Tuple([]))

  let source =
    e.case_(
      e.variable("a"),
      [#("Foo", p.Variable(""), e.access(e.variable("a"), "foo"))],
    )
  assert t.Record([#("a", t.Record([#("foo", _)], _))], _) =
    shake(source, t.Tuple([]))
}

pub fn case_shadowing_test() {
  let source =
    e.case_(e.variable("a"), [#("Foo", p.Variable("b"), e.variable("b"))])
  // There is a case for passing though inner types from functions etc
  assert t.Record([#("a", _)], _) = shake(source, t.Tuple([]))
}
