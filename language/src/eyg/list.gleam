import gleam/io
import gleam/list
import language/ast.{Destructure}
import language/ast/builder.{
  call, case_, constructor, function, let_, row, tuple_, var, varient,
}
import language/scope
import language/type_.{Data, Variable}

fn reverse() {
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

fn map() {
  let_(
    "do_map",
    function(
      ["input", "func", "accumulator"],
      case_(
        var("input"),
        [
          #(
            Destructure("Cons", ["next", "remaining"]),
            call(
              var("self"),
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
          #(Destructure("Nil", []), call(var("reverse"), [var("accumulator")])),
        ],
      ),
    ),
    function(
      ["input", "func"],
      call(var("do_map"), [var("input"), var("func"), call(var("Nil"), [])]),
    ),
  )
}

// zip needs tuple and result
// Module typer needs to go accross everywhere
pub fn module() {
  // Nominal/Named
  varient(
    "list::List",
    [1],
    [
      constructor("Cons", [Variable(1), Data("list::List", [Variable(1)])]),
      constructor("Nil", []),
    ],
    let_(
      "reverse",
      reverse(),
      let_(
        "map",
        map(),
        row([
          #("Cons", var("Cons")),
          #("Nil", var("Nil")),
          #("reverse", var("reverse")),
          #("map", var("map")),
        ]),
      ),
    ),
  )
}

pub fn return_tuple() {
  // Nominal/Named
  varient(
    "List",
    [1],
    [
      constructor("Cons", [Variable(1), Data("List", [Variable(1)])]),
      constructor("Nil", []),
    ],
    let_(
      "reverse",
      reverse(),
      let_(
        "map",
        map(),
        tuple_([var("Cons"), var("Nil"), var("reverse"), var("map")]),
      ),
    ),
  )
}
