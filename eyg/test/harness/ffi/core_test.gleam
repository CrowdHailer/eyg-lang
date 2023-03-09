// import eyg/analysis/typ as t
// import eyg/analysis/inference
// import eyg/runtime/interpreter as r
// import eygir/expression as e
// import harness/ffi/core
// import harness/ffi/integer
// import harness/ffi/linked_list
// import harness/ffi/env
// import gleeunit/should

// pub fn unequal_test() {
//   let #(types, values) =
//     env.init()
//     |> env.extend("equal", core.equal())

//   let prog = e.Apply(e.Apply(e.Variable("equal"), e.Integer(1)), e.Integer(2))
//   let sub = inference.infer(types, prog, t.Unbound(-1), t.Open(-2))

//   inference.type_of(sub, [])
//   |> should.equal(Ok(t.boolean))

//   r.eval(prog, values, r.Value)
//   |> should.equal(r.Value(core.false))
// }

// pub fn equal_test() {
//   let #(types, values) =
//     env.init()
//     |> env.extend("equal", core.equal())

//   let prog =
//     e.Apply(e.Apply(e.Variable("equal"), e.Binary("foo")), e.Binary("foo"))
//   let sub = inference.infer(types, prog, t.Unbound(-1), t.Open(-2))

//   inference.type_of(sub, [])
//   |> should.equal(Ok(t.boolean))

//   r.eval(prog, values, r.Value)
//   |> should.equal(r.Value(core.true))
// }

// pub fn simple_fix_test() {
//   let #(types, values) =
//     env.init()
//     |> env.extend("fix", core.fix())
//   let prog = e.Apply(e.Variable("fix"), e.Lambda("_", e.Binary("foo")))
//   let sub = inference.infer(types, prog, t.Unbound(-10), t.Closed)

//   inference.sound(sub)
//   |> should.equal(Ok(Nil))
//   inference.type_of(sub, [])
//   |> should.equal(Ok(t.Binary))

//   r.eval(prog, values, r.Value)
//   |> should.equal(r.Value(r.Binary("foo")))
// }

// pub fn no_recursive_fix_test() {
//   let #(types, values) =
//     env.init()
//     |> env.extend("fix", core.fix())
//   let prog =
//     e.Apply(
//       e.Apply(e.Variable("fix"), e.Lambda("_", e.Lambda("x", e.Variable("x")))),
//       e.Integer(1),
//     )
//   let sub = inference.infer(types, prog, t.Unbound(-10), t.Closed)

//   inference.sound(sub)
//   |> should.equal(Ok(Nil))
//   inference.type_of(sub, [])
//   |> should.equal(Ok(t.Integer))

//   r.eval(prog, values, r.Value)
//   |> should.equal(r.Value(r.Integer(1)))
// }

// pub fn recursive_sum_test() {
//   let #(types, values) =
//     env.init()
//     |> env.extend("fix", core.fix())
//     |> env.extend("ffi_add", integer.add())
//     |> env.extend("ffi_pop", linked_list.pop())

//   let list =
//     e.Apply(
//       e.Apply(e.Cons, e.Integer(1)),
//       e.Apply(e.Apply(e.Cons, e.Integer(3)), e.Tail),
//     )

//   let switch =
//     e.Apply(
//       e.Apply(
//         e.Case("Ok"),
//         e.Lambda(
//           "split",
//           e.Apply(
//             e.Apply(
//               e.Variable("self"),
//               e.Apply(
//                 e.Apply(e.Variable("ffi_add"), e.Variable("total")),
//                 e.Apply(e.Select("head"), e.Variable("split")),
//               ),
//             ),
//             e.Apply(e.Select("tail"), e.Variable("split")),
//           ),
//         ),
//       ),
//       e.Apply(
//         e.Apply(e.Case("Error"), e.Lambda("_", e.Variable("total"))),
//         e.NoCases,
//       ),
//     )
//   let sum =
//     e.Lambda(
//       "self",
//       e.Lambda(
//         "total",
//         e.Lambda(
//           "items",
//           e.Apply(switch, e.Apply(e.Variable("ffi_pop"), e.Variable("items"))),
//         ),
//       ),
//     )
//   let prog =
//     e.Apply(e.Apply(e.Apply(e.Variable("fix"), sum), e.Integer(0)), list)
//   let sub = inference.infer(types, prog, t.Unbound(-10), t.Closed)

//   inference.sound(sub)
//   |> should.equal(Ok(Nil))
//   inference.type_of(sub, [])
//   |> should.equal(Ok(t.Integer))

//   r.eval(prog, values, r.Value)
//   |> should.equal(r.Value(r.Integer(4)))
// }
