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


  todo("finish lists")
}

pub fn compiler() {
  let_("unify", function([#(Nil, "t1"), #(Nil, "t2")], var("t1")), var("unify"))
  |> ast.infer([])
}
