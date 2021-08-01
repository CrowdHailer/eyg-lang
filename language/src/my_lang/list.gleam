import gleam/io
import gleam/list
import language/ast.{Destructure}
import language/ast/builder.{call, case_, function, let_, var}
import language/scope
import language/type_.{Data, Function, Variable}

pub fn types() {
  scope.new()
  |> scope.newtype(
    "List",
    [1],
    [#("Cons", [Variable(1), Data("List", [Variable(1)])]), #("Nil", [])],
  )
  |> scope.newtype("Pair", [1, 2], [#("Pair", [Variable(1), Variable(2)])])
}

pub fn reverse() {
  let_(
    "do_reverse",
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
    ),
    function(
      ["input"],
      call(var("do_reverse"), [var("input"), call(var("Nil"), [])]),
    ),
  )
}

pub fn map() {
  function(
    ["input", "func"],
    call(
      function(
        ["input", "func", "accumulator"],
        case_(
          var("input"),
          [
            #(
              Destructure("Cons", ["next", "remaining"]),
              call(
                var("self"),
                // TODO if arg lengths don't equal throw error
                [
                  var("remaining"),
                  var("func"),
                  call(
                    var("Cons"),
                    [call(var("func"), [var("next")]), var("accumulator")],
                  ),
                ],
              ),
            ),
                    #(
              Destructure("Nil", []),
              call(var("reverse"), [var("accumulator")]),
            ),

          ],
        ),
      ),
      [var("input"), var("func"), call(var("Nil"), [])],
    ),
  )
}

// zip needs tuple and result
// returning a module needs tuple or pair or row
fn with(named, final) {
  list.reverse(named)
  |> list.fold(
    final,
    fn(assignment, in) {
      let #(name, value) = assignment
      let_(name, value, in)
    },
  )
}

// Module typer needs to go accross everywhere
pub fn module() {
  with(
    [#("reverse", reverse()), #("map", map())],
    call(var("Pair"), [var("reverse"), var("map")]),
  )
}
