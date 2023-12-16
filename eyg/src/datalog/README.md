# Magpie

This module is a datalog implementation, the datalog module in this repo was originally created as an embedded gleam DSL.

Old magpie is hardcoded to a triple store and doesn't implement recursion.
New one based much more on proper datalog.
Development of a Gleam app shouldn't need the eyg shell, or at least it doesn't work well

I have a cozy project that lines up with the AST output
String to cozo query exists in shell. COZO only accepts string queries

Typechecking my queries is new, as is using that in a structural editor the old magpie had a useful builder

lustre doesn't work well for for binding to key presses in text areas but it might be more robust with locations defined not using text
Data sources are built up in the shell

should states be kept in the program. No so there is no hole
If there is no hole how do we type check
Original magpie book uses the datomic syntax. Not the nicest to specify named rules

Goal
- informative errors
- nice builders


facts as tables. -> drop CSV's etc -> drop AST's because AST's belong in the clip board
rules as text.
table title as text down the side

original magpie rendering is good for objects, but does that work if not objects.
Shell or pulling into a language is far more interesting
(# 
  (:- (path))
  (:- (path a b) :- (edge a b) | (edge a x) (edge x b))
)

Spreadsheet is the view into this data
Triples exist in cozo.ast

// fn main() -> Nil {
//     result2()
//     foo(5, 3, x)
// }

// // membership.user.name
// {Q, name, age, team: id} <- {
//     user: {name, age: > 18},
//     team: {id}
// }

//  <- {cast: {name: "Arnold swartzeneger"}, director: {name}, title}

// ping pictures through the whole graph
// // tree through AST

// pattern match == datalog
// {id, ancestor: parent} <- {id, parent}
// {id, ancestor} <- {id, parent: {ancestor}},

// {id, unrelated} <- not {id, ancestor}, {id: unrelated, ancestor}

// <- {chars}
//   ,{chars starts_with "game "}
//     let directed_by = {
//     }

// {
//     use d <-var()
//     //
//     use <- directed_by(d, "Arnold", ignore)
//     // done()
// }
