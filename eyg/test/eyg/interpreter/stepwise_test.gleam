import gleam/io
import gleam/dynamic
import gleam/list
import gleam/map
import gleam/option.{None}
import gleam/string
import eyg/analysis
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter as r
import eyg/interpreter/tail_call
import eyg/interpreter/stepwise
import eyg/typer
import eyg/typer/monotype as t
import eyg/codegen/javascript

pub fn walk_tuple_test() {
    let empty = map.new()
    let source = e.tuple_([e.tuple_([]), e.binary("hello")])

    assert stepwise.Cont(value, cont) = stepwise.step(source, empty, stepwise.Done) 
    assert r.Tuple([]) = value
    assert stepwise.Cont(value, cont) = cont(value)
    assert r.Binary("hello") = value
    assert stepwise.Cont(value,_) = cont(value)
    assert r.Tuple([r.Tuple([]), r.Binary("hello")]) = value
    // TODO for some reason we get done twice at the end.
    // Maybe there is a zero position value that we don't need to worry about
}


pub fn process_test() {
    let empty = map.new()
    |> map.insert("spawn", r.BuiltinFn(stepwise.spawn))
    |> map.insert("x", r.Binary("really a function"))
    let source = e.call(e.call(e.variable("spawn"), e.variable("x")), e.function(p.Variable("pid"), e.variable("pid")))

    assert stepwise.Cont(value, cont) = stepwise.step(source, empty, stepwise.Done) 
    |> io.debug
    // assert r.Tuple([]) = value
    assert stepwise.Cont(value, cont) = cont(value)
    |> io.debug
    assert stepwise.Cont(value, cont) = cont(value)
    |> io.debug
    assert stepwise.Cont(value, cont) = cont(value)
    |> io.debug
    assert stepwise.Cont(value, cont) = cont(value)
    |> io.debug
    assert stepwise.Cont(value, cont) = cont(value)
    |> io.debug

    assert r.Binary("hello") = value
    // TODO for some reason we get done twice at the end.
    // Maybe there is a zero position value that we don't need to worry about
}

