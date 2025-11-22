import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import gleeunit/should

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
