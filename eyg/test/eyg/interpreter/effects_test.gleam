import gleam/io
import gleam/option.{None, Some}
import gleam/map
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter as r
import eyg/interpreter/effectful
import eyg/typer
import eyg/typer/monotype as t
import eyg/typer/polytype
import eyg/analysis


fn log(term) { 
    e.call(e.variable("effect"), e.tagged("Log", term))
}

fn log_twice() { 
    e.let_(p.Variable("a"), log(e.binary("hello")), e.let_(p.Variable("b"), log(e.binary("world")), e.tuple_([])))
}

fn log_computation() { 
    e.function(p.Tuple([]), log_twice())
}

pub fn unhandled_effect_test() {
    let source = log_twice()
    assert Ok(r.Effect("Log", r.Binary("hello"), cont)) = effectful.eval(source)
    assert Ok(r.Effect("Log", r.Binary("world"), cont)) = cont(r.Tuple([]))

    assert Ok(r.Tuple([])) = cont(r.Tuple([]))
}

pub fn unhandled_effect_nested_test() {
    let source = e.call(log_computation(), e.tuple_([]))
    assert Ok(r.Effect("Log", r.Binary("hello"), cont)) = effectful.eval(source)
    assert Ok(r.Effect("Log", r.Binary("world"), cont)) = cont(r.Tuple([]))

    assert Ok(r.Tuple([])) = cont(r.Tuple([]))
}

pub fn functions_test()  {
    let source = e.call(e.function(p.Tuple([]), e.binary("return")), e.tuple_([]))
    assert Ok(r.Binary("return")) = effectful.eval(source)
}

fn collect_logs() { 
    e.let_(p.Variable("collect_logs"),
        e.function(p.Variable("effect"), e.case_(e.variable("effect"), [
            #("Log", p.Tuple(["e", "k"]), 
                e.let_(p.Tuple(["list", "value"]), e.call(e.call(e.call(e.variable("handle"), e.variable("collect_logs")), e.variable("k")), e.tuple_([])),
                    e.tuple_([e.tagged("Cons", e.tuple_([e.variable("e"), e.variable("list")])), e.variable("value")])
                ) 
            ),
            #("Pure", p.Variable("value"), e.tuple_([e.tagged("Nil", e.tuple_([])), e.variable("value")])),    
        ])),
        e.variable("collect_logs")
    )
}

pub fn handled_effect_test()  {
    let source = log_computation()
    let handler = collect_logs()
    let handled = e.call(e.call(e.variable("handle"), handler), source)
    assert Ok(r.Tuple([logs, value])) = effectful.eval(e.call(handled, e.tuple_([])))
    assert r.Tagged("Cons", r.Tuple([r.Binary("hello"), r.Tagged("Cons", r.Tuple([r.Binary("world"), r.Tagged("Nil", r.Tuple([]))]))])) = logs
    assert r.Tuple([]) = value    
}

// Ask in unison what logging with the same effect but different types should do.

// todo union never is not the type because it will return the effect handler result
// I can't work out what should be value of effect type
const effect_fn = #("effect", polytype.Polytype([-99], t.Function(t.Union([], Some(-99)), t.Union([], None), t.Row([], Some(-99)))))

pub fn effect_literal_test() {
    let source = log(e.binary("hello"))
    let #(typed, typer) = analysis.infer(source, t.Unbound(-1), [effect_fn])
    assert [] = typer.inconsistencies
    assert Ok(t.Union([], None)) = analysis.get_type(typed, typer)
    // Probably we want something around the effect types to be returned
}

const log_fn = #("log", polytype.Polytype([1], t.Function(t.Binary, t.Tuple([]), t.Row([#("Log", t.Binary)], Some(1)))))
const abort_fn = #("abort", polytype.Polytype([1], t.Function(t.Tuple([]), t.Tuple([]), t.Row([#("Abort", t.Tuple([]))], Some(1)))))

pub fn single_effect_test() {
    let source = e.call(e.variable("log"), e.binary("my log"))

    // I think effect type should just be union
    // open effects space
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Row([], Some(-2)), [log_fn])
    assert t.Union([#("Log", t.Binary)], Some(_)) = t.resolve(t.Union([], Some(-2)), typer.substitutions)
    assert [] = typer.inconsistencies

    // unbound term of effect
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Row([#("Log", t.Unbound(-2))], None), [log_fn])
    assert t.Binary = t.resolve(t.Unbound(-2), typer.substitutions)
    assert [] = typer.inconsistencies

    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Row([#("Log", t.Binary)], None), [log_fn])
    assert [] = typer.inconsistencies

    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Row([#("Log", t.Tuple([]))], None), [log_fn])
    assert [#([0], typer.UnmatchedTypes(t.Tuple([]), t.Binary))] = typer.inconsistencies

    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Row([], None), [log_fn])
    assert [#([0], typer.UnexpectedFields([#("Log", t.Binary)]))] = typer.inconsistencies

    io.debug("here")
    // function test
    let source = e.function(p.Tuple([]), source)
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Row([], None), [log_fn])
    assert [] = typer.inconsistencies
    io.debug(typer.substitutions)
    assert t.Binary = t.resolve(t.Unbound(-1), typer.substitutions)
    |> io.debug
}

pub fn multiple_call_effect_test() {
    let source = e.call(e.variable("abort"), e.call(e.variable("log"), e.binary("my log")))

    // I think effect type should just be union
    // open effects space
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Row([], Some(-2)), [log_fn, abort_fn])
    assert [] = typer.inconsistencies
    assert t.Union([#("Abort", t.Tuple([])), #("Log", t.Binary)], Some(_)) = t.resolve(t.Union([], Some(-2)), typer.substitutions)

    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Row([#("Log", t.Tuple([]))], None), [log_fn, abort_fn])
    assert [
        #([1, 0], typer.UnmatchedTypes(t.Tuple([]), t.Binary)),
        #([0], typer.UnexpectedFields([#("Abort", t.Tuple([]))])),        
    ] = typer.inconsistencies
}

pub fn multiple_let_effect_test() {
    let source = e.let_(p.Tuple([]), e.call(e.variable("log"), e.binary("my log")),
        e.call(e.variable("abort"), e.tuple_([]))
    )
    
    // I think effect type should just be union
    // open effects space
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Row([], Some(-2)), [log_fn, abort_fn])
    assert [] = typer.inconsistencies
    assert t.Union([#("Log", t.Binary), #("Abort", t.Tuple([]))], Some(_)) = t.resolve(t.Union([], Some(-2)), typer.substitutions)

    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Row([#("Log", t.Tuple([]))], None), [log_fn, abort_fn])
    assert [
        #([2, 0], typer.UnexpectedFields([#("Abort", t.Tuple([]))])),        
        #([1, 0], typer.UnmatchedTypes(t.Tuple([]), t.Binary)),
    ] = typer.inconsistencies
}