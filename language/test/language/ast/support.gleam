import language/scope
import language/type_.{Data, Function, PolyType, Variable}

pub fn with_equal(scope) {
  scope
  |> scope.newtype("Boolean", [], [#("True", []), #("False", [])])
  |> scope.set_variable(
    "equal",
    PolyType([1], Function([Variable(1), Variable(1)], Data("Boolean", []))),
  )
}
