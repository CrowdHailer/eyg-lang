import gleam/io
import gleam/list
import gleam/string
import eyg/typer/monotype as t
import eyg/typer
import eyg/typer/harness

pub fn compile_unconstrained(expression, harness) {
  // }
  // pub fn compile() -> Nil {
  let harness.Harness(variables, native_to_string) = harness
  let p = typer.init(native_to_string)
  let scope = typer.root_scope(variables)
  let #(x, typer) = typer.next_unbound(p)
  let expected = t.Unbound(x)
  let #(typed, typer) = typer.infer(expression, expected, #(typer, scope))
  // use inital scope again Can use local scope as EVERYTHIN immutable
  typer.expand_providers(typed, typer)
}
// pub fn compile(expected, untyped) {
//   let scope =
//     typer.root_scope([
//       #("equal", typer.equal_fn()),
//       #("harness", harness.string()),
//     ])
//   let state = #(typer.init(browser_to_string), scope)
//   let #(typed, typer) = typer.infer(untyped, expected, state)
//   let #(typed, typer) = typer.expand_providers(typed, typer)
//   case typer.inconsistencies {
//     [] -> fn(handle) {
//       let #(ok, _) = handle
//       ok(javascript.eval(typed, typer, browser_to_string))
//     }
//     inconsistencies -> fn(handle) {
//       let #(_, err) = handle
//       err(string.join(list.map(
//         inconsistencies,
//         fn(x: #(List(Int), String)) { x.1 },
//       )))
//     }
//   }
// }
