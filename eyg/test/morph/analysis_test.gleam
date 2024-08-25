import eygir/annotated as a
import gleam/io
import gleam/listx
import gleam/option.{None}
import gleam/pair
import gleeunit/should
import gleeunit/shouldx
import morph/analysis
import morph/editable as e
import morph/projection as p

pub fn scope_vars_test() {
  let context = analysis.empty_environment()
  let source = #(p.Exp(e.Vacant("")), [p.Body([e.Bind("x")])])
  analysis.scope_vars(source, context)
  |> shouldx.contain1()
  |> pair.first
  |> should.equal("x")
}

pub fn nested_let_test() {
  // let b1 = ""
  // let b2 = ""
  // let outer = {
  //   let inner = 10
  //   ???
  // }
  // let after = {}
  // ???
  let context = analysis.empty_environment()
  let source = #(p.Exp(e.Vacant("")), [
    p.BlockTail([#(e.Bind("inner"), e.Integer(10))]),
    p.BlockValue(
      e.Bind("outer"),
      [#(e.Bind("b2"), e.String("")), #(e.Bind("b1"), e.String(""))],
      [#(e.Bind("after"), e.Record([], None))],
      e.Vacant(""),
    ),
  ])

  analysis.scope_vars(source, context)
  |> listx.keys
  |> should.equal(["inner", "b2", "b1"])
}
// we currently only index into the body of the match in the case statement
// pub fn branch_type_test() {
//   let source =
//     e.Case(
//       e.Variable("value"),
//       [#("J", e.Vacant("isJ")), #("K", e.Vacant("isK"))],
//       None,
//     )
//   e.to_annotated(source, [])
//   |> should.equal(
//     #(
//       a.Apply(
//         #(
//           a.Apply(
//             #(a.Apply(#(a.Case("J"), [0, 1]), #(a.Vacant("isJ"), [1, 1])), [1]),
//             #(
//               a.Apply(
//                 #(a.Apply(#(a.Case("K"), [0, 2]), #(a.Vacant("isK"), [1, 2])), [
//                   2,
//                 ]),
//                 #(a.NoCases, [3]),
//               ),
//               [2],
//             ),
//           ),
//           [1],
//         ),
//         #(a.Variable("value"), [0]),
//       ),
//       [],
//     ),
//   )

//   let source =
//     e.Case(
//       e.Call(e.Tag("Ok"), [e.String("Yo")]),
//       [
//         #("Ok", e.Vacant("")),
//         #("Error", e.Function([e.Bind("reason")], e.Integer(3))),
//       ],
//       None,
//     )
//   e.to_annotated(source, [])
//   // |> should.equal(#(a.Apply))
//   todo
//   let proj = p.focus_at(source, [1, 0])
//   analysis.scope_vars(proj, analysis.empty_environment())
//   |> io.debug
//   io.debug(p.path(proj))
//   analysis.analyse(proj, analysis.empty_environment())
//   |> analysis.print
//   todo
// }
