import gleam/io
import language/ast.{Destructure}
import language/ast/builder.{call, case_, function, let_, var}
import language/scope
import language/type_.{Data, Function, Variable}

pub fn lists() {
  let scope =
    scope.new()
    |> scope.newtype(
      "List",
      [1],
      [#("Cons", [Variable(1), Data("List", [Variable(1)])]), #("Nil", [])],
    )
  // call this reverse and test fns separatly
  // Can I type check variables in PolyType vs MonoType. probably not easily if iterating one at a time.
  // Although go through each arg if Poly in quantified new i if not same i
  let untyped =
    function(
      ["remaining", "reversed"],
      case_(
        var("remaining"),
        [
          #(
            Destructure("Cons", ["next", "remaining"]),
            call(
              var("self"),
              [
                var("remaining"),
                call(var("Cons"), [var("next"), var("reversed")]),
              ],
            ),
          ),
          #(Destructure("Nil", []), var("reversed")),
        ],
      ),
    )
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope)
  let Function([Data("List", [a]), Data("List", [b])], Data("List", [r])) =
    type_.resolve_type(type_, substitutions)
  let True = a == r
  let True = b == r
  Ok(Nil)
}
