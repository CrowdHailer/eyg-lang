//// Persistent continuation machine for native JavaScript values and functions.
//// JavaScript emitted by the compiler constructs these steps; all dispatch,
//// delimiters, resumptions and fold control flow live here.

import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/javascript/array
import gleam/list
import gleam/option.{type Option, None, Some}
import javascript/mutable_reference as reference
import plinthx/javascript/foreign

pub type Step {
  Call(function: Dynamic, argument: Dynamic)
  Bind(value: Dynamic, then: fn(Dynamic) -> Dynamic)
  Handle(label: String, handler: Dynamic, body: Dynamic)
  ShallowCall(
    label: String,
    handler: Dynamic,
    on_return: Dynamic,
    body: Dynamic,
  )
  Perform(label: String, value: Dynamic)
  MaskCall(label: String, body: Dynamic)
  PureCall(function: Dynamic, argument: Dynamic)
  Resume(value: Dynamic, frames: List(Frame))
}

pub type Frame {
  Then(fn(Dynamic) -> Dynamic)
  Delimiter(String, Dynamic, Option(Dynamic))
  MaskBoundary(String)
  PureBoundary
}

pub type Metrics {
  Metrics(depth: Int, captured: Int)
}

/// One runtime owns its host handler and counters; captured frame lists are immutable.
pub type Runtime {
  Runtime(
    run: fn(Dynamic) -> Dynamic,
    function_: fn(Dynamic) -> Dynamic,
    call: fn(Dynamic, Dynamic) -> Dynamic,
    bind: fn(Dynamic, fn(Dynamic) -> Dynamic) -> Dynamic,
    bind_builtin: fn(Dynamic) -> fn(Dynamic) -> Dynamic,
    handle: fn(String, Dynamic, Dynamic) -> Dynamic,
    shallow: fn(String, Dynamic, Dynamic, Dynamic) -> Dynamic,
    perform: fn(String, Dynamic) -> Dynamic,
    mask: fn(String, Dynamic) -> Dynamic,
    pure_: fn(Dynamic) -> Dynamic,
    fix: fn(Dynamic) -> Dynamic,
    list_fold: fn(Dynamic) -> fn(Dynamic) -> fn(Dynamic) -> Dynamic,
    binary_fold: fn(Dynamic) -> fn(Dynamic) -> fn(Dynamic) -> Dynamic,
    never: fn(Dynamic) -> Dynamic,
    metrics: fn() -> Metrics,
  )
}

// This FFI only recognizes values made by Gleam's generated constructors.
@external(javascript, "./runtime_ffi.mjs", "step")
fn as_step(value: Dynamic) -> Option(Step)

pub fn create(host: Dynamic) -> Runtime {
  let metrics = reference.new(Metrics(0, 0))
  Runtime(
    run: run(_, host, metrics),
    function_: function_(_, host, metrics),
    call: call,
    bind: bind,
    bind_builtin: fn(value) {
      fn(then) { bind(value, fn(value) { call(then, value) }) }
    },
    handle: fn(label, handler, body) {
      foreign.to_dynamic(Handle(label, handler, body))
    },
    shallow: fn(label, handler, on_return, body) {
      foreign.to_dynamic(ShallowCall(label, handler, on_return, body))
    },
    perform: fn(label, value) { foreign.to_dynamic(Perform(label, value)) },
    mask: fn(label, body) { foreign.to_dynamic(MaskCall(label, body)) },
    pure_: guarded(_, host, metrics),
    fix: fixed(_, host, metrics),
    list_fold: fn(items) {
      fn(initial) { fn(reducer) { fold_list(items, initial, reducer) } }
    },
    binary_fold: fn(bytes) {
      fn(initial) { fn(reducer) { fold_binary(bytes, 0, initial, reducer) } }
    },
    never: fn(_) { fail("IncorrectTerm", dynamic.string("Never")) },
    metrics: fn() { reference.get(metrics) },
  )
}

fn call(function, argument) {
  foreign.to_dynamic(Call(function, argument))
}

fn bind(value, then) {
  foreign.to_dynamic(Bind(value, then))
}

fn function_(body, host, metrics) {
  foreign.wrap(body, fn(function, argument) {
    run(call(function, argument), host, metrics)
  })
}

fn run(value, host, metrics) {
  reference.set(metrics, Metrics(0, 0))
  loop(value, [], host, metrics)
}

fn loop(value, stack, host, metrics) {
  let previous = reference.get(metrics)
  reference.set(
    metrics,
    Metrics(..previous, depth: int.max(previous.depth, list.length(stack))),
  )
  case as_step(value) {
    Some(Call(function, argument)) -> {
      let next =
        foreign.apply(foreign.body(function), array.from_list([argument]))
      loop(next, stack, host, metrics)
    }
    Some(Bind(value, then)) -> loop(value, [Then(then), ..stack], host, metrics)
    Some(Handle(label, handler, body)) ->
      loop(
        call(body, unit()),
        [Delimiter(label, handler, None), ..stack],
        host,
        metrics,
      )
    Some(ShallowCall(label, handler, on_return, body)) ->
      loop(
        call(body, unit()),
        [Delimiter(label, handler, Some(on_return)), ..stack],
        host,
        metrics,
      )
    Some(MaskCall(label, body)) ->
      loop(call(body, unit()), [MaskBoundary(label), ..stack], host, metrics)
    Some(PureCall(function, argument)) ->
      loop(call(function, argument), [PureBoundary, ..stack], host, metrics)
    Some(Perform(label, value)) ->
      case find(stack, label, [], 0) {
        Error(kind) -> fail(kind, dynamic.string(label))
        Ok(None) -> {
          let next =
            foreign.apply(host, array.from_list([dynamic.string(label), value]))
          loop(next, stack, host, metrics)
        }
        Ok(Some(#(handler, outside, frames))) -> {
          let previous = reference.get(metrics)
          reference.set(
            metrics,
            Metrics(
              ..previous,
              captured: int.max(previous.captured, list.length(frames)),
            ),
          )
          let resume =
            function_(
              foreign.to_dynamic(fn(value) {
                foreign.to_dynamic(Resume(value, frames))
              }),
              host,
              metrics,
            )
          let next =
            bind(call(handler, value), fn(handler) { call(handler, resume) })
          loop(next, outside, host, metrics)
        }
      }
    Some(Resume(value, frames)) -> {
      let stack =
        list.fold(frames, stack, fn(stack, frame) { [frame, ..stack] })
      loop(value, stack, host, metrics)
    }
    None -> {
      let value = case foreign.is_function(value) && !foreign.has_body(value) {
        True -> function_(value, host, metrics)
        False -> value
      }
      case stack {
        [] -> value
        [Then(then), ..rest] -> loop(then(value), rest, host, metrics)
        [Delimiter(_, _, None), ..rest] -> loop(value, rest, host, metrics)
        [Delimiter(_, _, Some(on_return)), ..rest] ->
          loop(call(on_return, value), rest, host, metrics)
        [MaskBoundary(_), ..rest] | [PureBoundary, ..rest] ->
          loop(value, rest, host, metrics)
      }
    }
  }
}

// Captured frames are reversed for reinstallation, without links outside the delimiter.
fn find(stack, label, frames, skip) {
  case stack {
    [] if skip > 0 -> Error("MaskedEffect")
    [] -> Ok(None)
    [PureBoundary, ..] -> Error("ImpureEffect")
    [MaskBoundary(found) as frame, ..rest] if found == label ->
      find(rest, label, [frame, ..frames], skip + 1)
    [Delimiter(found, _, _) as frame, ..rest] if found == label && skip > 0 ->
      find(rest, label, [frame, ..frames], skip - 1)
    [Delimiter(found, handler, on_return) as frame, ..rest] if found == label -> {
      let frames = case on_return {
        None -> [frame, ..frames]
        Some(_) -> frames
      }
      Ok(Some(#(handler, rest, frames)))
    }
    [frame, ..rest] -> find(rest, label, [frame, ..frames], skip)
  }
}

fn guarded(function, host, metrics) {
  case foreign.is_function(function) {
    False -> fail("IncorrectTerm", dynamic.string("Function"))
    True ->
      function_(
        foreign.to_dynamic(fn(argument) {
          foreign.to_dynamic(PureCall(function, argument))
        }),
        host,
        metrics,
      )
  }
}

fn fixed(builder, host, metrics) {
  let saved = reference.new(None)
  let self =
    function_(
      foreign.to_dynamic(fn(argument) {
        let assert Some(self) = reference.get(saved)
        bind(call(builder, self), fn(function) { call(function, argument) })
      }),
      host,
      metrics,
    )
  reference.set(saved, Some(self))
  call(builder, self)
}

fn fold_list(items, initial, reducer) {
  case foreign.length(items) {
    0 -> initial
    _ ->
      bind(call(reducer, foreign.index(items, 0)), fn(function) {
        bind(call(function, initial), fn(next) {
          fold_list(foreign.index(items, 1), next, reducer)
        })
      })
  }
}

fn fold_binary(bytes, offset, initial, reducer) {
  case offset == foreign.length(bytes) {
    True -> initial
    False ->
      bind(call(reducer, foreign.index(bytes, offset)), fn(function) {
        bind(call(function, initial), fn(next) {
          fold_binary(bytes, offset + 1, next, reducer)
        })
      })
  }
}

fn unit() {
  foreign.object(array.from_list([]))
}

fn fail(label, value) {
  foreign.object(
    array.from_list([
      #("eygBreak", foreign.object(array.from_list([#(label, value)]))),
    ]),
  )
  |> foreign.raise
}
