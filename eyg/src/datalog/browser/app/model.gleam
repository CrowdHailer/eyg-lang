import datalog/ast
import datalog/ast/builder.{fact, i, n, rule, v, y}

pub type Model {
  Model(sections: List(Section))
}

pub type Section {
  Query(List(ast.Constraint))
  Source(relation: String, table: List(List(ast.Value)))
  Paragraph(String)
}

pub fn initial() {
  Model([
    Paragraph(
      "f the top-level goal clause is read as the denial of the problem, then the empty clause represents false and the proof of the empty clause is a refutation of the denial of the problem. If the top-level goal clause is read as the problem itself, then the empty clause represents true, and the proof of the empty clause is a proof that the problem has a solution.",
    ),
    Query([fact("Edge", [i(1), i(2)]), fact("Edge", [i(7), i(3)])]),
    Paragraph(
      "lorem simsadf asjdf a.fiuwjfiowqej  vs.df.asdf.aweifqjhwoefj sf  sdf ds f sdf sd f sdf
  aefdsdfj;fi waepfjlla   a f af awefqafoh;dlfdsf",
    ),
    {
      let x1 = v("x")
      let x2 = v("y")
      let x3 = v("z")
      Query([rule("Path", [x1], [y("Edge", [x1, x2]), y("Path", [x2, x3])])])
    },
    {
      let x1 = v("x")
      Query([rule("Foo", [x1], [y("Edge", [x1, i(2)]), n("Path", [x1, x1])])])
    },
  ])
}
