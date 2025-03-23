import eyg/interpreter/block
import eyg/interpreter/expression
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/io
import gleam/javascript/promise
import gleam/option.{None}
import gleeunit/should
import website/components/runner
import website/sync/cache

pub fn simple_expression_test() {
  let cache = cache.init()
  let extrinsic = []
  let source = ir.add(ir.integer(1), ir.integer(2))
  let runner =
    runner.init(
      expression.execute(source, []),
      cache,
      extrinsic,
      expression.resume,
    )
  runner.return
  |> should.equal(Ok(v.Integer(3)))
}

pub fn block_expression_test() {
  let cache = cache.init()
  let extrinsic = [
    #("Foo", fn(_) { Ok(fn() { promise.resolve(v.String("From Foo")) }) }),
  ]
  let source =
    ir.let_(
      "x",
      ir.apply(ir.perform("Foo"), ir.unit()),
      ir.let_("y", ir.string("world"), ir.vacant()),
    )
  let runner =
    runner.init(block.execute(source, []), cache, extrinsic, block.resume)
  let #(runner, action) = runner.update(runner, runner.Start)
  let assert runner.RunExternalHandler(ref, thunk) = action
  use message <- promise.await(runner.run_thunk(ref, thunk))
  let #(runner, action) = runner.update(runner, message)

  let #(value, env) =
    runner.return
    |> should.be_ok
  value
  |> should.equal(None)
  env
  |> should.equal([
    #("y", v.String(value: "world")),
    #("x", v.String(value: "From Foo")),
  ])
  action
  |> should.equal(runner.Conclude(#(value, env)))
  promise.resolve(Nil)
}
