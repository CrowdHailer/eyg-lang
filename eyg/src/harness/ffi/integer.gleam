import gleam/int
import eyg/runtime/interpreter as r
import harness/ffi/cast

// import harness/ffi/spec.{
//   build, empty, end, integer, lambda, record, string, union, variant,
// }

pub fn add() {
  r.Arity2(do_add)
}

fn do_add(left, right, k) {
  use left <- cast.integer(left)
  use right <- cast.integer(right)
  r.continue(k, r.Integer(left + right))
}
// pub fn subtract() {
//   lambda(integer(), lambda(integer(), integer()))
//   |> build(fn(x) { fn(y) { x - y } })
// }

// pub fn multiply() {
//   lambda(integer(), lambda(integer(), integer()))
//   |> build(fn(x) { fn(y) { x * y } })
// }

// pub fn divide() {
//   lambda(integer(), lambda(integer(), integer()))
//   |> build(fn(x) { fn(y) { x / y } })
// }

// pub fn absolute() {
//   lambda(integer(), integer())
//   |> build(fn(x) { int.absolute_value(x) })
// }

// pub fn int_parse() {
//   lambda(
//     string(),
//     union(variant("Ok", integer(), variant("Error", record(empty()), end()))),
//   )
//   |> build(fn(raw) {
//     fn(ok) {
//       fn(error) {
//         case int.parse(raw) {
//           Ok(i) -> ok(i)
//           Error(_) -> error(Nil)
//         }
//       }
//     }
//   })
// }

// pub fn int_to_string() {
//   lambda(integer(), string())
//   |> build(fn(x) { int.to_string(x) })
// }
