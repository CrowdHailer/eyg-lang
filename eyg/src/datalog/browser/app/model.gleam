import datalog/ast
import datalog/ast/builder.{fact, i, n, rule, v, y}

pub type Model {
  Model(sections: List(Section))
}

pub type Section {
  Query(List(ast.Constraint))
  Paragraph(String)
}

pub fn initial() {
  Model([
    Paragraph(
      "f the top-level goal clause is read as the denial of the problem, then the empty clause represents false and the proof of the empty clause is a refutation of the denial of the problem. If the top-level goal clause is read as the problem itself, then the empty clause represents true, and the proof of the empty clause is a proof that the problem has a solution.
The solution of the problem is a substitution of terms for the variables X in the top-level goal clause, which can be extracted from the resolution proof. Used in this way, goal clauses are similar to conjunctive queries in relational databases, and Horn clause logic is equivalent in computational power to a universal Turing machine.
Van Emden and Kowalski (1976) investigated the model-theoretic properties of Horn clauses in the context of logic programming, showing that every set of definite clauses D has a unique minimal model M. An atomic formula A is logically implied by D if and only if A is true in M. It follows that a problem P represented by an existentially quantified conjunction of positive literals is logically implied by D if and only if P is true in M. The minimal model semantics of Horn clauses is the basis for the stable model semantics of logic programs.[8] ",
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
