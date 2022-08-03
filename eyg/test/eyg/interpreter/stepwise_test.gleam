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
    |> map.insert("send", r.BuiltinFn(stepwise.send))
    |> map.insert("x", r.Binary("really a function"))
    let source = e.call(e.call(e.variable("spawn"), e.variable("x")), e.function(p.Variable("pid"), 
    e.call(e.call(e.variable("send"), e.tuple_([e.variable("pid"), e.binary("Post")])), e.function(p.Variable("_sent"), e.variable("pid"))  )
    
    ))

    // assert stepwise.Cont(value, cont) = stepwise.step(source, empty, stepwise.Done) 
    // |> io.debug
    // // assert r.Tuple([]) = value
    // assert stepwise.Cont(value, cont) = cont(value)
    // |> io.debug
    // assert stepwise.Cont(value, cont) = cont(value)
    // |> io.debug
    // assert stepwise.Cont(value, cont) = cont(value)
    // |> io.debug
    // assert stepwise.Cont(value, cont) = cont(value)
    // |> io.debug
    // assert stepwise.Cont(value, cont) = cont(value)
    // |> io.debug

    // assert r.Binary("hello") = value
    // TODO rename so not empty
    stepwise.effect_eval(source, empty)
    |> io.debug()
    // TODO for some reason we get done twice at the end.
    // Maybe there is a zero position value that we don't need to worry about
}


// TODO callbacks needed otherwise type system can't see whats happening Need to be wrapped up in a bigger type
// System(Int) needs a done(Int) although most of the time done is tuple
// Needs to call out to external fn because types can't be dynamic and that is needed to convert specific message types to dynamic list that can be reordered
// Having anon functions that are applied on actor don't work because if there is a message ahead then there is no mutable reference that allows new state to be pulled
// Is there a way to pop out one value and go depth first, but early messages might never be delivered and how do I resume with updated state

// Message type is safe because it is just object type in runtime

pub fn dom_test() {
    let source = e.function(p.Variable("browser"), 
        e.let_(p.Variable("ui"), e.access(e.variable("browser"), "ui"),
        e.call(
            e.call(e.variable("send"), e.tuple_([e.variable("ui"), e.binary("hello")])),
            e.function(p.Variable(""), e.call(e.variable("send"), e.tuple_([e.variable("ui"), e.binary("goodby")])))
        )
        )
    )

    stepwise.start(source, map.new())
    |> io.debug
}