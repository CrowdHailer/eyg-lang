import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state.{Delimit, Empty, Stack, Trace}
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/option.{None}

pub fn tail_resumption_reuses_trace_test() {
  // handle Ping((_, resume) -> { resume({}) }, (_) -> {
  //   let _ = perform Ping({})
  //   vacant
  // })
  let handler =
    ir.lambda(
      "_",
      ir.lambda("resume", ir.apply(ir.variable("resume"), ir.unit())),
    )
  let body =
    ir.lambda(
      "_",
      ir.let_("_", ir.apply(ir.perform("Ping"), ir.unit()), ir.vacant()),
    )
  let source = ir.apply(ir.apply(ir.handle("Ping"), handler), body)

  let assert Error(#(break.Vacant, _, _, stack)) =
    expression.execute(source, [])
  let assert Stack(Trace(_, _), _, stack) = stack
  let assert Stack(Delimit("Ping", _, _, None), _, stack) = stack
  // The tail resumption replaces the handler's Trace instead of adding one.
  let assert Stack(Trace(_, _), _, Empty) = stack
}

pub fn tail_call_reuses_trace_test() {
  // let g = (_) -> { vacant }
  // let f = (_) -> { g({}) }
  // f({})
  let source =
    ir.let_(
      "g",
      ir.lambda("_", ir.vacant()),
      ir.let_(
        "f",
        ir.lambda("_", ir.apply(ir.variable("g"), ir.unit())),
        ir.apply(ir.variable("f"), ir.unit()),
      ),
    )

  let assert Error(#(break.Vacant, _, _, stack)) =
    expression.execute(source, [])
  // Calling g replaces f's Trace instead of adding one.
  let assert Stack(Trace(_, _), _, Empty) = stack
}

/// without the selective pushing of trace frames when calling a closure the stack grows per iteration
pub fn fixed_tail_recursion_reuses_trace_test() {
  // let loop = !fix((self, n) -> {
  //   match !int_compare(n, 0) {
  //     Eq(_) -> { vacant } // Inspect the stack before returning 0.
  //     | (_) -> { self(!int_subtract(n, 1)) }
  //   }
  // })
  // loop(10000)
  let compare =
    ir.apply(
      ir.apply(ir.builtin("int_compare"), ir.variable("n")),
      ir.integer(0),
    )
  let recur =
    ir.apply(
      ir.variable("self"),
      ir.apply(
        ir.apply(ir.builtin("int_subtract"), ir.variable("n")),
        ir.integer(1),
      ),
    )
  let body =
    ir.apply(
      ir.apply(
        ir.apply(ir.case_("Eq"), ir.lambda("_", ir.vacant())),
        ir.lambda("_", recur),
      ),
      compare,
    )
  let loop =
    ir.apply(ir.builtin("fix"), ir.lambda("self", ir.lambda("n", body)))
  let source = ir.apply(loop, ir.integer(10_000))

  let assert Error(#(break.Vacant, _, env, stack)) =
    expression.execute(source, [])
  let assert Stack(Trace(_, _), _, Empty) = stack
  assert expression.resume(v.Integer(0), env, stack) == Ok(v.Integer(0))
}
