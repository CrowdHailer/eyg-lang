import gleam/io
import gleam/dynamic
import gleam/list
import gleam/map
import gleam/option.{None}
import gleam/string
import eyg/analysis
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter.{exec} as r
import eyg/typer
import eyg/typer/monotype as t
import eyg/codegen/javascript

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

fn tail() { 
    r.Tagged("Nil", r.Tuple([]))
}

fn cons(h,t) {
     r.Tagged("Cons", r.Tuple([h, t]))

}

pub fn recursive_test() {
    let source = e.let_(
        p.Variable("move"),
        e.function(p.Tuple(["from", "to"]), 
            e.case_(e.variable("from"), [
                #("Nil", p.Tuple([]), e.variable("to")),
                #("Cons", p.Tuple(["item", "from"]), e.let_(
                    p.Variable("to"),
                    e.tagged("Cons", e.tuple_([e.variable("item"), e.variable("to")])),
                    e.call(e.variable("move"), e.tuple_([e.variable("from"), e.variable("to")]))
                ))
            ])
        ),
        e.call(e.variable("move"), e.variable("x"))
    )
    let empty = map.new()
    |> map.insert("x", r.Tuple([tail(), tail()]))
    assert r.Tagged("Nil", r.Tuple([])) = exec(source, empty) 

        let empty = map.new()
    |> map.insert("x", r.Tuple([cons(r.Binary("1"),cons(r.Binary("2"),tail())), tail()]))
    assert r.Tagged("Cons", r.Tuple([r.Binary("2"), r.Tagged("Cons", r.Tuple([r.Binary("1"), r.Tagged("Nil", r.Tuple([]))]))])) = exec(source, empty) 
    |> io.debug
}

pub fn builtin_test()  {
    let env = map.new()
    |> map.insert("string", r.Record([#("reverse", r.BuiltinFn(fn(object) {
        assert r.Binary(value) = object
        r.Binary(string.reverse(value))
    }))]))
    let source = e.call(e.access(e.variable("string"), "reverse"), e.binary("hello"))

    assert r.Binary("olleh") = exec(source, env) 
}



fn capture(object) { 
    assert r.Function(pattern, body, captured, None) = object
    let func = e.function(pattern, body)

    let source = e.call(func, e.binary("DOM"))

    let #(typed, typer) = analysis.infer(source, t.Unbound(-1), [])
    let #(typed, typer) = typer.expand_providers(typed, typer, [])
    // We shouldn't need to type check again or expand providers as this will have be done on the first pass
    // However the render function takes typed AST not untyped and I don't want to fix that now.
    //   assert [] = typer.inconsistencies

    
    list.map(map.to_list(captured), r.render_var)
    |> list.append([javascript.render_to_string(typed, typer)])
    |> string.join("\n")
    |> io.debug()
    |> javascript.do_eval()
    |> io.debug()
    r.Tuple([])
 }

pub fn capture_test()  {
    let source = e.let_(
        p.Variable("message"), 
        e.binary("hello"),
        e.call(e.variable("capture"), e.function(p.Variable("name"),
            e.tuple_([e.variable("message"), e.variable("name")])
        ))
    )

    let env = map.new()
    |> map.insert("capture", r.BuiltinFn(capture))
    assert r.Tuple([]) = exec(source, env) 
}

pub fn coroutines_test() {
    let source = e.call(
        e.call(e.variable("spawn"), e.let_(p.Variable("loop"), e.function(p.Variable("message"), e.variable("loop")), e.variable("loop"))),
        e.function(p.Variable("pid"), e.variable("pid"))
    )

    let env = map.new()
    |> map.insert("spawn", r.BuiltinFn(r.spawn))
    assert #(r.Pid(0), coroutines) = r.run(source, env, []) 
}

// send -> dispatch ~~~> deliver -> receive
// Value(x)
// Effect(send: List(Int, Value), spawn)
// Spawn iterate can take out key