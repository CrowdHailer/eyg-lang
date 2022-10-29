import gleam/io
import gleam/list
import gleam/map
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/effectful
import eyg/interpreter/interpreter as r
import eyg/analysis/shake
import eyg/typer/monotype as t
import eyg/codegen/javascript/runtime

pub fn fetch_used_variables_test() {
  let source =
    e.let_(
      p.Variable("a"),
      e.record([#("foo", e.binary("foo")), #("bar", e.binary("bar"))]),
      e.let_(
        p.Variable("b"),
        e.tuple_([]),
        e.function(
          p.Variable("x"),
          e.tuple_([e.variable("x"), e.variable("a")]),
        ),
      ),
    )
  // Currently testing for code set up in cli.req
  assert Ok(term) = effectful.eval(source)
  assert r.Function(pattern, body, captured, self) = term
  let picked = shake.shake_function(pattern, body, captured, self)

  // maybe shake is more like walk/findrequirements
  assert r.Record([
    #("a", r.Record([#("foo", r.Binary("foo")), #("bar", r.Binary("bar"))])),
  ]) = picked
}

pub fn fetch_used_fields_test() {
  let source =
    e.let_(
      p.Variable("a"),
      e.record([#("foo", e.binary("foo")), #("bar", e.binary("bar"))]),
      e.function(p.Variable(""), e.access(e.variable("a"), "foo")),
    )
  // Currently testing for code set up in cli.req
  assert Ok(term) = effectful.eval(source)
  assert r.Function(pattern, body, captured, self) = term
  let picked = shake.shake_function(pattern, body, captured, self)

  // maybe shake is more like walk/findrequirements
  assert r.Record([#("a", r.Record([#("foo", r.Binary("foo"))]))]) = picked
}

pub fn builtins_test() {
  let source =
    e.function(p.Tuple([]), e.access(e.variable("builtin"), "append"))
  assert Ok(term) = effectful.eval(source)
  assert r.Function(pattern, body, captured, self) = term
  let picked = shake.shake_function(pattern, body, captured, self)
  assert r.Record([#("builtin", r.Record([#("append", builtin)]))]) = picked
  assert r.BuiltinFn(b) = builtin

  // Difference between builtin an global
  // A builtin io console.log might be returned when it actually should be, I think effects capture this
  // This is a good reason to lookup in env and if it's new panic
  // assert
  assert Ok(r.Record(globals)) = map.get(effectful.env(), "builtin")
  assert Ok("append") = runtime.render_builtin(b, globals)
}

// TODO I think recursive records are possible and can be shaken

pub fn recursive_fn_test() {
  // DOES runtime handle recursion properly
  let source =
    e.let_(
      p.Variable("loop"),
      e.function(p.Variable(""), e.call(e.variable("loop"), e.tuple_([]))),
      e.variable("loop"),
    )
  // Currently testing for code set up in cli.req
  assert Ok(term) = effectful.eval(source)
  assert r.Function(pattern, body, captured, self) = term
  let picked = shake.shake_function(pattern, body, captured, self)

  // maybe shake is more like walk/findrequirements
  assert r.Record([]) = picked
}
// pub fn debug_rec_test() {
//   let source =
//     e.let_(
//       p.Variable("main"),
//       e.function(
//         p.Variable("dom"),
//         e.let_(
//           p.Variable("loop"),
//           e.let_(
//             p.Tuple([]),
//             e.variable("render"),
//             e.function(
//               p.Variable("state"),
//               e.call(e.variable("dom"), e.binary("actions")),
//             ),
//           ),
//           e.variable("loop"),
//         ),
//       ),
//       e.variable("main"),
//     )
//   let source =
//     e.let_(
//       p.Variable("a"),
//       e.binary("Value A"),
//       e.let_(
//         p.Variable("f"),
//         e.function(p.Tuple([]), e.variable("a")),
//         e.variable("f"),
//       ),
//     )
//   assert Ok(term) = effectful.eval(source)
//   assert r.Function(pattern, body, captured, self) = term
//   io.debug(captured)
//   let picked = shake.shake_function(pattern, body, captured, self)

//   // maybe shake is more like walk/findrequirements
//   assert r.Record([]) =
//     picked
//     |> io.debug
//   todo("test")
// }
