import birdie
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import gleeunit/should

fn snapshot(type_, width: Int, title: String) -> Nil {
  debug.render(type_, width)
  |> birdie.snap(title: title)
}

pub fn primitive_types_match_legacy_rendering_test() {
  t.Integer
  |> debug.render(80)
  |> should.equal("Integer")

  t.Binary
  |> debug.render(80)
  |> should.equal("Binary")

  t.String
  |> debug.render(80)
  |> should.equal("String")

  t.Never
  |> debug.render(80)
  |> should.equal("Never")
}

pub fn small_list_test() {
  t.List(t.String)
  |> debug.render(80)
  |> should.equal("List(String)")
}

pub fn small_record_test() {
  t.record([#("name", t.String), #("age", t.Integer)])
  |> debug.render(80)
  |> should.equal("{name: String, age: Integer}")
}

pub fn small_union_test() {
  t.option(t.Integer)
  |> debug.render(80)
  |> should.equal("[Some: Integer | None: {}]")
}

pub fn small_promise_test() {
  t.Promise(t.String)
  |> debug.render(80)
  |> should.equal("Promise(String)")
}

pub fn pure_function_test() {
  t.Fun(t.Integer, t.Empty, t.String)
  |> debug.mono()
  |> should.equal("(Integer) -> String")
}

pub fn multiple_argument_function_test() {
  t.Fun(t.Integer, t.Empty, t.Fun(t.Integer, t.Empty, t.String))
  |> debug.mono()
  |> should.equal("(Integer, Integer) -> String")
}

pub fn open_function_test() {
  t.Fun(t.Integer, t.Var(1), t.String)
  |> debug.mono()
  |> should.equal("(Integer <..1>) -> String")
}

pub fn closed_effectful_function_test() {
  t.Fun(
    t.Integer,
    t.EffectExtend(
      "Abort",
      #(t.String, t.unit),
      t.EffectExtend("Count", #(t.unit, t.Integer), t.Empty),
    ),
    t.String,
  )
  |> debug.mono()
  |> should.equal(
    "(Integer <Abort(↑String ↓{}), Count(↑{} ↓Integer)>) -> String",
  )
}

pub fn open_effectful_function_test() {
  t.Fun(
    t.Integer,
    t.EffectExtend("Abort", #(t.String, t.unit), t.Var(2)),
    t.String,
  )
  |> debug.mono()
  |> should.equal("(Integer <Abort(↑String ↓{}), ..2>) -> String")
}

pub fn polymorphic_effect_test() {
  let f = t.Fun(t.String, t.Var(0), t.String)
  t.Fun(f, t.Empty, t.Fun(t.Integer, t.Var(0), t.String))
  |> debug.mono()
  |> should.equal("((String <..0>) -> String, Integer <..0>) -> String")
}

pub fn long_record_breaks_test() {
  t.record([
    #("name", t.String),
    #("content", t.Binary),
    #("attempts", t.Integer),
    #("result", t.result(t.String, t.record([#("message", t.String)]))),
  ])
  |> snapshot(28, "large type record breaks across lines")
}

pub fn long_effectful_function_breaks_test() {
  t.Fun(
    t.record([#("path", t.String), #("bytes", t.Binary)]),
    t.EffectExtend(
      "ReadFile",
      #(t.String, t.result(t.Binary, t.String)),
      t.EffectExtend(
        "DecodeJSON",
        // this is a confusing example because the DecodeJSON effect doesn't return an AST.
        // But it does make a long example
        #(t.Binary, t.result(t.ast(), t.String)),
        t.Var(7),
      ),
    ),
    t.Promise(t.List(t.record([#("key", t.String), #("value", t.ast())]))),
  )
  |> snapshot(40, "large effectful function breaks across lines")
}
