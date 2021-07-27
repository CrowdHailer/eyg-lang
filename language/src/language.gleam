import language/ast.{Constructor, Variable, function, let_, newtype, var}

pub fn lists() {
  let environment =
    newtype(
      "List",
      [1],
      [
        #("Cons", [Variable(1), Constructor("List", [Variable(1)])]),
        #("Nil", []),
      ],
    )

  // let untyped = let_("do_reverse", function([]))

  todo("finish lists")
}

pub fn compiler() {
  let_("unify", function(["t1", "t2"], var("t1")), var("unify"))
  |> ast.infer([])
}
