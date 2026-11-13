import eyg/compiled/runtime
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/list
import plinthx/javascript/foreign

fn new() {
  runtime.create(foreign.to_dynamic(fn(_, value) { value }))
}

fn function(rt: runtime.Runtime, body: fn(Dynamic) -> Dynamic) {
  rt.function_(foreign.to_dynamic(body))
}

fn integer(value) {
  let assert Ok(value) = decode.run(value, decode.int)
  value
}

fn unit() {
  foreign.object(array.from_list([]))
}

pub fn deep_handlers_shadow_outer_handlers_and_resume_each_effect_test() {
  let rt = new()
  let handler = fn(n) {
    function(rt, fn(_) {
      foreign.to_dynamic(fn(resume) { rt.call(resume, dynamic.int(n)) })
    })
  }
  let body =
    function(rt, fn(_) {
      rt.bind(rt.perform("Ping", unit()), fn(a) {
        rt.bind(rt.perform("Ping", unit()), fn(b) {
          dynamic.int(integer(a) + integer(b))
        })
      })
    })
  let inner = function(rt, fn(_) { rt.handle("Ping", handler(1), body) })
  assert rt.run(rt.handle("Ping", handler(100), inner)) == dynamic.int(2)
}

pub fn captured_continuations_support_independent_multiple_resumptions_test() {
  let rt = new()
  let handler =
    function(rt, fn(_) {
      foreign.to_dynamic(fn(resume) {
        rt.bind(rt.call(resume, dynamic.int(10)), fn(a) {
          rt.bind(rt.call(resume, dynamic.int(20)), fn(b) {
            dynamic.int(integer(a) + integer(b))
          })
        })
      })
    })
  let body =
    function(rt, fn(_) {
      rt.bind(rt.perform("Choose", unit()), fn(n) {
        dynamic.int(integer(n) + 1)
      })
    })
  assert rt.run(rt.handle("Choose", handler, body)) == dynamic.int(32)
}

pub fn pure_fixed_tail_recursion_does_not_use_the_host_call_stack_test() {
  let rt = new()
  let builder =
    foreign.to_dynamic(fn(self) {
      foreign.to_dynamic(fn(n) {
        case integer(n) {
          0 -> dynamic.int(42)
          n -> rt.call(self, dynamic.int(n - 1))
        }
      })
    })
  assert rt.run(
      rt.bind(rt.fix(builder), fn(self) { rt.call(self, dynamic.int(100_000)) }),
    )
    == dynamic.int(42)
  assert rt.metrics().depth <= 2
}

fn stateful(rt: runtime.Runtime, count) {
  let items =
    list.fold(
      list.repeat(unit(), count),
      foreign.to_dynamic(array.from_list([])),
      fn(tail, head) { foreign.to_dynamic(array.from_list([head, tail])) },
    )
  let handler =
    function(rt, fn(_) {
      foreign.to_dynamic(fn(resume) {
        foreign.to_dynamic(fn(state) {
          let next = dynamic.int(integer(state) + 1)
          rt.bind(rt.call(resume, unit()), fn(rest) { rt.call(rest, next) })
        })
      })
    })
  let reducer =
    function(rt, fn(_) {
      foreign.to_dynamic(fn(_) { rt.perform("Increment", unit()) })
    })
  let body =
    function(rt, fn(_) {
      rt.bind(rt.list_fold(items)(unit())(reducer), fn(_) {
        foreign.to_dynamic(fn(state) { state })
      })
    })
  rt.run(
    rt.bind(rt.handle("Increment", handler, body), fn(run) {
      rt.call(run, dynamic.int(0))
    }),
  )
}

pub fn state_passing_handlers_keep_bounded_frames_and_captures_test() {
  let rt = new()
  assert stateful(rt, 10) == dynamic.int(10)
  let small = rt.metrics()
  assert small.depth > 0
  assert small.captured > 0
  assert stateful(rt, 10_000) == dynamic.int(10_000)
  assert rt.metrics() == small
}

pub fn partially_applied_functions_remain_callable_by_the_host_test() {
  let rt = new()
  let add =
    function(rt, fn(a) {
      foreign.to_dynamic(fn(b) { dynamic.int(integer(a) + integer(b)) })
    })
  let partial = foreign.apply(add, array.from_list([dynamic.int(20)]))
  assert foreign.apply(partial, array.from_list([dynamic.int(22)]))
    == dynamic.int(42)
}
