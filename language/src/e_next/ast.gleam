// import gleam/option.{None, Option, Some}
// import gleam/string
// import gleam/list

// // Sum type is variant
// // product type is tuple
// // Record has fields consisting of name x
// // In Eval Term can be an expression
// // In Pattern Term can be a label
// pub type Term(t, l) {
//   Var(l)
//   Binary
//   // Constructor/Name
//   Variant(String, t)
//   // If I put in Term for nesting
//   Tuple(List(t))
// }

// //   Tuple(List(Expression(l, t)))
// //   
// // Named taking a Type mean needs empty tuple for None True False etc
// pub type MonoType {
//   // Named or Nominal or Sum
//   Named
//   // Tuple or Product
//   TTuple
//   Unbound(Int)
//   // label + value = Field in Record
//   // a -> b nearer HM 
//   Function
// }

// pub type Node(l, t) {
//   // Let rule in HM
//   Case(
//     subject: Expression(l, t),
//     clauses: List(#(Option(String), l, Expression(l, t))),
//   )
//   //   // Is Bind Case of one term?
//   Bind(Term(#(t, l), l), Expression(l, t), Expression(l, t))
//   //   var rule
//   Eval(Term(t, l))
//   //   application rule
//   Call
//   //   Abstraction rule
//   Fn
// }

// pub type Expression(l, t) =
//   #(t, Node(l, t))

// fn bind(pattern, subject, context) {
//   case pattern {
//     Var(label) -> {
//       let pattern = Var(#(label, 1))
//       Ok(#(pattern, context))
//     }
//     // type_name, varient
//     Variant(variant, _) -> todo
//   }
// }

// pub type Checker {
//   Checker(next_unbound: Int, scope: List(Int))
// }

// // fn try_map_state(
// //   list: List(a),
// //   initial: s,
// //   func: fn(a, s) -> Result(#(b, s), e),
// // ) -> Result(#(List(b), s), e) {
// //   do_try_map_state(list, initial, func, [])
// // }
// // fn do_try_map_state(list, state, func, accumulator) {
// //   case list {
// //     [] -> Ok(#(list.reverse(accumulator), state))
// //     [item, ..list] -> {
// //       let #(item, state) = func(item, state)
// //       let accumulator = [item, ..accumulator]
// //       do_try_map_state(list, state, func, accumulator)
// //     }
// //   }
// // }
// fn map_state(
//   list: List(a),
//   initial: s,
//   func: fn(a, s) -> #(b, s),
// ) -> #(List(b), s) {
//   do_map_state(list, initial, func, [])
// }

// fn do_map_state(list, state, func, accumulator) {
//   case list {
//     [] -> #(list.reverse(accumulator), state)
//     [item, ..list] -> {
//       let #(item, state) = func(item, state)
//       let accumulator = [item, ..accumulator]
//       do_map_state(list, state, func, accumulator)
//     }
//   }
// }

// // Start testing with tuple and then row
// // put pattern type_ and ast in different folders. 
// // scope is part of type_
// fn infer(
//   expression: #(Nil, Node(String, Nil)),
//   context: Checker,
// ) -> Result(#(Expression(String, MonoType), Checker), Nil) {
//   let #(Nil, tree) = expression
//   case tree {
//     Bind(pattern, value, then) -> {
//       try #(value, context) = infer(value, context)
//       case pattern {
//         Tuple(elements) -> {
//           let #(elements, context) =
//             map_state(
//               elements,
//               context,
//               fn(element, context) {
//                 let #(Nil, label) = element
//                 // generate_type_var(context)
//                 // set_variable(context)
//                 #(#(Unbound(1), #(label, 1)), context)
//               },
//             )
//           todo
//           // string.concat(keys)
//           // TODO unify type_.Tuple()
//           todo
//         }
//       }
//       todo
//     }
//     Case(subject, clauses) -> {
//       try #(subject, context) = infer(subject, context)
//       let Checker(scope: scope, ..) = context
//       let [#(variant, label, then), ..clauses] = clauses
//       Ok(#(subject, context))
//     }
//   }
// }
