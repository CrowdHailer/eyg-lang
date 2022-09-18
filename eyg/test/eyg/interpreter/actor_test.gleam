import gleam/io
import gleam/list
import gleam/map
import gleam/option.{Some}
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter as r
import eyg/interpreter/tail_call
import eyg/interpreter/actor

pub fn start_a_process_test() {
  let loop =
    e.let_(
      p.Variable("loop"),
      e.function(p.Variable("message"), e.variable("loop")),
      e.variable("loop"),
    )
  let source =
    e.call(
      e.call(e.variable("spawn"), loop),
      e.function(
        p.Variable("pid"),
        e.call(
          e.call(
            e.variable("send"),
            e.tuple_([e.variable("pid"), e.binary("Hello")]),
          ),
          e.function(
            p.Variable(""),
            e.call(e.variable("done"), e.variable("pid")),
          ),
        ),
      ),
    )
  assert Ok(#(value, processes, messages)) = actor.eval_source(source, 0, [])
  assert r.Pid(0) = value
  assert [process] = processes
  assert r.Function(_, _, _, Some("loop")) = process
  assert [message] = messages
  assert r.Tuple([r.Pid(0), r.Binary("Hello")]) = message
}

fn logger(x) {
  io.debug(x)
  Ok(r.Tagged("Return", r.BuiltinFn(logger)))
}

pub fn logger_process_test() {
  let source =
    e.call(
      e.call(
        e.variable("send"),
        e.tuple_([e.variable("logger"), e.binary("My Log line")]),
      ),
      e.function(p.Variable(""), e.tagged("Return", e.binary("sent"))),
    )
  let global = [#("logger", r.BuiltinFn(logger))]
  assert Ok(#(_, [process])) = actor.run_source(source, global)
  assert True = process == r.BuiltinFn(logger)
}

fn ast_spawn(loop, cont) {
  e.call(e.call(e.variable("spawn"), loop), cont)
}

fn ast_send(pid, message, then) {
  e.call(
    e.call(e.variable("send"), e.tuple_([pid, message])),
    e.function(p.Variable(""), then),
  )
}

pub fn spawning_process_does_nothing_unless_returned_test() {
  let loop =
    e.let_(
      p.Variable("loop"),
      e.function(p.Variable("message"), e.variable("loop")),
      e.variable("loop"),
    )
  let source =
    e.let_(
      p.Variable(""),
      ast_spawn(loop, e.function(p.Variable(""), e.tuple_([]))),
      e.tagged("Return", e.binary("then")),
    )
  assert Ok(#(_, [])) = actor.run_source(source, [])
}

pub fn sending_does_nothing_unless_returned_test() {
  let source =
    e.let_(
      p.Variable(""),
      ast_send(e.variable("pid"), e.binary("message"), e.tuple_([])),
      e.tagged("Return", e.binary("then")),
    )
  // This doesn't have a real function behind pid
  assert Ok(#(value, [], [])) =
    actor.eval_source(source, 0, [#("pid", r.Tuple([]))])
}
