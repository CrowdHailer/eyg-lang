
// import language/ast.{
//   Constructor, Destructure, Name, Variable, call, case_, function, let_, newtype,
//   var,
// }
// pub fn lists() {
//   let environment =
//     newtype(
//       "List",
//       [1],
//       [
//         #("Cons", [Variable(1), Constructor("List", [Variable(1)])]),
//         #("Nil", []),
//       ],
//     )
//   let untyped =
//     let_(
//       "do_reverse",
//       function(
//         ["remaining", "reversed"],
//         case_(
//           var("remaining"),
//           [
//             // Need recursion 
//             #(
//               Destructure("Cons", ["next", "remaining"]),
//               call(
//                 var("do_reverse"),
//                 [
//                   var("remaining"),
//                   call(var("Cons"), [var("next"), var("reversed")]),
//                 ],
//               ),
//             ),
//             #(Destructure("Nil", []), var("todo")),
//           ],
//         ),
//       ),
//       var("todo"),
//     )
//   let Ok(_) = ast.infer(untyped, environment)
// }
// pub fn compiler() {
//   let_("unify", function(["t1", "t2"], var("t1")), var("unify"))
//   |> ast.infer([])
// }
