import gleam/io
import gleam/dynamic
import gleam/map
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter.{exec} as r

pub fn tuples_test() {
    let empty = map.new()
    let source = e.tuple_([e.tuple_([]), e.binary("hello")])

    assert r.Tuple([r.Tuple([]), r.Binary("hello")]) = exec(source, empty)
}

pub fn tuple_patterns_test() {
    let empty = map.new()
    let source = e.let_(
        p.Tuple(["x", "y"]), 
        e.tuple_([e.binary("foo"), e.binary("bar")]), 
        e.tuple_([e.variable("y"), e.variable("x")])
        )

    assert r.Tuple([r.Binary("bar"), r.Binary("foo")]) = exec(source, empty)
}


pub fn records_test() {
    let empty = map.new()
    let source = e.access(e.record([#("foo", e.tuple_([]))]), "foo")

    assert r.Tuple([]) = exec(source, empty) 
}

pub fn variables_test() {
    let empty = map.new()
    let source = e.let_(p.Variable("a"), e.tuple_([]), e.variable("a"))

    assert r.Tuple([]) = exec(source, empty)
}

pub fn functions_test() {
    let empty = map.new()
    let source = e.call(e.function(p.Variable("x"), e.variable("x")), e.tuple_([]))

    assert r.Tuple([]) = exec(source, empty) 

        let source = e.call(e.function(p.Tuple([]), e.binary("inner")), e.tuple_([]))

    assert r.Binary("inner") = exec(source, empty) 

}

pub fn unions_test() {
        let empty = map.new()
    let source = e.case_(e.tagged("True", e.tuple_([])), [
        #("False", p.Tuple([]), e.binary("no")),
        #("True", p.Tuple([]), e.binary("yes"))
    ])
    assert r.Binary("yes") = exec(source, empty) 

            let empty = map.new()
    let source = e.case_(e.tagged("Some", e.binary("foo")), [
        #("Some", p.Variable("a"), e.variable("a")),
        #("None", p.Tuple([]), e.binary("BAD"))
    ])
    assert r.Binary("foo") = exec(source, empty) 

}
// TODO string reverse
// recursive eval