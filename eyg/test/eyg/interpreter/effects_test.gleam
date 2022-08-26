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


// TODO try/catch syntax does work with multi resume

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

pub fn effect_function_test() {
    let source = e.function(p.Tuple([]), log(e.binary("hello")))
    let #(typed, typer) = analysis.infer(source, t.Unbound(-1), [effect_fn])
    assert [] = typer.inconsistencies
    // io.debug("=========")
    // io.debug(typer.substitutions)
    // assert Ok(t.Union([], None)) = analysis.get_type(typed, typer)
    // |> io.debug
    // todo
    // I think there is a unify in call missing

    // call(f, x)
    // 
}

const log_fn = #("log", polytype.Polytype([], t.Function(t.Binary, t.Tuple([]), t.Row([#("Log", t.Binary)], None))))

pub fn external_log_fn_effect_test(){
    let source = e.function(p.Tuple([]), e.call(e.variable("log"), e.binary("my log")))
    let #(typed, typer) = analysis.infer(source, t.Unbound(-1), [log_fn])
    assert [] = typer.inconsistencies
    assert Ok(t.Function(t.Tuple([]), t.Tuple([]), effects)) = analysis.get_type(typed, typer)
    assert t.Row([#("Log", t.Binary)], None) = effects
    // I think potentially this should still expand i.e. effects has Some(_)
}

const abort_fn = #("abort", polytype.Polytype([], t.Function(t.Binary, t.Tuple([]), t.Row([#("Abort", t.Tuple([]))], None))))


// TODO check type error for binary logging/print a better name? and being sent the wrong type

pub fn effects_unify_test()  {
    assert Ok(typer) = typer.unify(
        t.Function(from: t.Unbound(i: 4), to: t.Unbound(i: 0), effects: t.Row(members: [], extra: Some(1))),
        t.Function(from: t.Binary, to: t.Tuple(elements: []), effects: t.Row(members: [#("Abort", t.Tuple(elements: []))], extra: None)),
        typer.Typer(
            next_unbound: 5, 
            substitutions: [
                #(1, t.Union(variants: [#("Log", t.Binary)], extra: None)), 
                #(2, t.Binary), 
                #(-1, t.Function(from: t.Tuple(elements: []), to: t.Unbound(i: 0), effects: t.Row(members: [], extra: Some(1))))
                ], 
            inconsistencies: [])

    )
    io.debug("out")
    io.debug(typer.substitutions)
    todo("effects_unify_test")
}

pub fn multiple_effect_test(){
    let source = e.function(p.Tuple([]), e.let_(
        p.Tuple([]),
        e.call(e.variable("log"), e.binary("my log")),
        e.call(e.variable("abort"), e.binary("my log"))
    ))
    let #(typed, typer) = analysis.infer(source, t.Unbound(-1), [log_fn, abort_fn])
    assert [] = typer.inconsistencies
    |> io.debug
    assert Ok(t.Function(t.Tuple([]), t.Tuple([]), effects)) = analysis.get_type(typed, typer)
    io.debug("xxx")
    io.debug(typer.substitutions)
    assert t.Row([#("Log", t.Binary)], None) = effects
    |> io.debug
    // I think potentially this should still expand i.e. effects has Some(_)
}

pub fn bin_log_test() {
    let source = e.let_(p.Variable(""), e.call(e.variable("log"), e.binary("my log")), e.tuple_([]))

    let #(typed, typer) = analysis.infer(source, t.Unbound(-1), [log_fn])
    assert Ok(t.Tuple([])) = analysis.get_type(typed, typer)
    assert [#([1, 0], typer.UnexpectedFields(_))] = typer.inconsistencies
    // effect [..1] -> 2 & {1}
    // log Binary -> [] & Log(Binary)
    // todo

    let source = e.function(p.Tuple([]), e.let_(p.Variable(""), e.call(e.variable("log"), e.binary("my log")), e.tuple_([])))

    let #(typed, typer) = analysis.infer(source, t.Function(t.Tuple([]), t.Tuple([]), t.Row([], Some(-1))), [log_fn])
    io.debug("one")
    // Which bit has a type of 1
    analysis.get_type(typed, typer)
    |> io.debug
    assert [] = typer.inconsistencies
}
// statefull pulling of value