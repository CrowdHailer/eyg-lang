import eyg/interpreter/builtin
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleeunit/should
import simplifile

// The state-passing handler in guides/examples/increment_counter.eyg, with a
// builtin fold as its workload so recursion in the workload cannot distort
// measurements of stack growth attributable to the handler.
fn counter() {
  let callback =
    ir.lambda(
      "_",
      ir.lambda(
        "resume",
        ir.lambda(
          "count",
          ir.let_(
            "next",
            ir.apply(
              ir.apply(ir.builtin("int_add"), ir.variable("count")),
              ir.integer(1),
            ),
            ir.apply(
              ir.apply(ir.variable("resume"), ir.unit()),
              ir.variable("next"),
            ),
          ),
        ),
      ),
    )
  let body =
    ir.lambda(
      "_",
      ir.let_(
        "_",
        workload(ir.apply(ir.perform("Increment"), ir.unit()), ir.unit()),
        ir.lambda("count", ir.variable("count")),
      ),
    )
  ir.apply(
    ir.apply(ir.apply(ir.handle("Increment"), callback), body),
    ir.integer(0),
  )
}

fn workload(action, initial) {
  ir.apply(
    ir.apply(ir.apply(ir.builtin("list_fold"), ir.variable("items")), initial),
    ir.lambda("_", ir.lambda("acc", action)),
  )
}

fn direct_counter() {
  workload(
    ir.apply(ir.apply(ir.builtin("int_add"), ir.variable("acc")), ir.integer(1)),
    ir.integer(0),
  )
}

fn with_state(label, body) {
  let callback =
    ir.lambda(
      "_",
      ir.lambda(
        "resume",
        ir.lambda("state", {
          ir.let_(
            "next",
            ir.apply(
              ir.apply(ir.builtin("int_add"), ir.variable("state")),
              ir.integer(1),
            ),
            ir.apply(
              ir.apply(ir.variable("resume"), ir.variable("next")),
              ir.variable("next"),
            ),
          )
        }),
      ),
    )
  let body =
    ir.lambda(
      "_",
      ir.let_(
        "value",
        body,
        ir.lambda(
          "state",
          ir.record([
            #("state", ir.variable("state")),
            #("value", ir.variable("value")),
          ]),
        ),
      ),
    )
  ir.apply(ir.apply(ir.apply(ir.handle(label), callback), body), ir.integer(0))
}

pub fn interleaved_stateful_handlers_stack_test() {
  let action =
    ir.let_(
      "_",
      ir.apply(ir.perform("Left"), ir.unit()),
      ir.let_("_", ir.apply(ir.perform("Right"), ir.unit()), ir.unit()),
    )
  let source =
    with_state("Left", with_state("Right", workload(action, ir.unit())))
  let #(_, limit, _) = run(source, 10)
  list.each([0, 10, 100, 1000, 10_000], fn(count) {
    let #(result, total, pending) = run(source, count)
    let wrapped = fn(value) {
      v.Record(
        dict.from_list([
          #("state", v.Integer(count)),
          #("value", value),
        ]),
      )
    }
    result |> should.equal(Ok(wrapped(wrapped(v.unit()))))
    io.println(
      "interleaved="
      <> int.to_string(count)
      <> " stack="
      <> int.to_string(total)
      <> " non_trace="
      <> int.to_string(pending),
    )
    { total <= limit } |> should.be_true
  })
}

fn depths(stack, total, pending) {
  case stack {
    state.Empty -> #(total, pending)
    state.Stack(state.Trace(..), _, rest) -> depths(rest, total + 1, pending)
    state.Stack(_, _, rest) -> depths(rest, total + 1, pending + 1)
  }
}

fn measure(next, max_total, max_pending) {
  case next {
    state.Break(result) -> #(result, max_total, max_pending)
    state.Loop(control, env, stack) -> {
      let #(total, pending) = depths(stack, 0, 0)
      measure(
        state.step(control, env, stack),
        int.max(total, max_total),
        int.max(pending, max_pending),
      )
    }
  }
}

fn run(source, count) {
  let env =
    builtin.default([
      #("items", v.LinkedList(list.repeat(v.unit(), count))),
      #("iterations", v.Integer(count)),
    ])
  measure(state.Loop(state.E(source), env, state.Empty), 0, 0)
}

pub fn shallow_state_replacement_has_bounded_stack_test() {
  let source =
    simplifile.read("../../spec/evaluation/shallow_counter.eyg")
    |> should.be_ok
    |> parser.all_from_string
    |> should.be_ok
    |> ir.clear_annotation
  let source = ir.apply(source, ir.variable("items"))
  let #(_, limit, _) = run(source, 10)
  list.each([0, 1, 10, 100, 1000, 10_000], fn(n) {
    let #(result, depth, _) = run(source, n)
    result |> should.equal(Ok(v.Integer(n)))
    { depth <= limit } |> should.be_true
  })
}

pub fn state_passing_count_and_stack_measurement_test() {
  let #(_, total_limit, pending_limit) = run(counter(), 10)
  let #(_, baseline_limit, _) = run(workload(ir.unit(), ir.unit()), 10)
  let #(_, direct_limit, _) = run(direct_counter(), 10)
  list.each([0, 10, 100, 1000, 10_000], fn(count) {
    let #(result, total, pending) = run(counter(), count)
    result |> should.equal(Ok(v.Integer(count)))
    let #(baseline, baseline_total, baseline_pending) =
      run(workload(ir.unit(), ir.unit()), count)
    baseline |> should.equal(Ok(v.unit()))
    let #(direct, direct_total, _) = run(direct_counter(), count)
    direct |> should.equal(Ok(v.Integer(count)))
    // Tail calls and resumptions must not retain redundant trace frames.
    { total <= total_limit } |> should.be_true
    { pending <= pending_limit } |> should.be_true
    { baseline_total <= baseline_limit } |> should.be_true
    { direct_total <= direct_limit } |> should.be_true
    io.println(
      "increments="
      <> int.to_string(count)
      <> " handler_stack="
      <> int.to_string(total)
      <> " handler_non_trace="
      <> int.to_string(pending)
      <> " baseline_stack="
      <> int.to_string(baseline_total)
      <> " baseline_non_trace="
      <> int.to_string(baseline_pending)
      <> " direct_counter_stack="
      <> int.to_string(direct_total),
    )
  })
}

pub fn fixed_tail_recursion_has_bounded_stack_test() {
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
        ir.apply(ir.case_("Eq"), ir.lambda("_", ir.integer(0))),
        ir.lambda("_", recur),
      ),
      compare,
    )
  let loop =
    ir.apply(ir.builtin("fix"), ir.lambda("self", ir.lambda("n", body)))
  let source = ir.apply(loop, ir.variable("iterations"))
  let #(_, limit, _) = run(source, 10)
  let #(result, total, _) = run(source, 10_000)
  result |> should.equal(Ok(v.Integer(0)))
  { total <= limit } |> should.be_true
}
