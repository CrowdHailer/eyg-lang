import gleam/io
import language/ast.{Destructure, call, case_, function, let_, var}
import language/scope
import language/type_.{Constructor, Variable}

pub fn lists() {
  let scope =
    scope.new()
    |> scope.newtype(
      "List",
      [1],
      [
        #("Cons", [Variable(1), Constructor("List", [Variable(1)])]),
        #("Nil", []),
      ],
    )
  let untyped = // let_(
    //   "do_reverse",
    function(
      ["remaining", "reversed"],
      case_(
        var("remaining"),
        [
          // Need recursion 
          #(
            Destructure("Cons", ["next", "remaining"]),
            call(
              var("self"),
              [
                var("remaining"),
                // Test unioning cons
                call(var("Cons"), [var("next"), var("reversed")]),
              ],
            ),
          ),
          #(Destructure("Nil", []), var("reversed")),
        ],
      ),
    )
  //   var("todo"),
  // )
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope)
  let Constructor("Function", [a, b, o]) =
    type_.resolve_type(type_, substitutions)
    |> io.debug()
  // let Constructor("List", [t]) = type_.resolve_type(a, substitutions)
  // TODO all variables should be equal
  let 1 = 0
  Ok(Nil)
}
// pub fn compiler() {
//   let_("unify", function(["t1", "t2"], var("t1")), var("unify"))
//   |> ast.infer([])
// }
