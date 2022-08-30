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
import eyg/editor/editor
import eyg/editor/type_info


fn log(term) { 
    e.call(e.variable("raise"), e.tagged("Log", term))
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
        e.function(p.Variable("raise"), e.case_(e.variable("raise"), [
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

// TODO union never is not the type because it will return the effect handler result
// I can't work out what should be value of effect type

// analysis.get_type shrinks unbound as well so we can't use that for checking 
fn get_sub_type(typed, typer: typer.Typer, path) { 
    assert Ok(element) = editor.get_expression(typed, path)
    try type_ = typer.get_type(element)
    Ok(t.resolve(type_, typer.substitutions))
 }

fn get_type(typed, typer){
    get_sub_type(typed, typer, [])
}

pub fn unbound_effect_literal_test() {
    let source = e.call(e.variable("raise"), e.tagged("Log", e.binary("hello")))
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [])

    assert [] = typer.inconsistencies
    assert Ok(t.Unbound(-1)) = get_type(typed, typer)
    assert t.Union([#("Log", t.Function(t.Binary, t.Unbound(-1), _))], Some(_)) = t.resolve(t.Unbound(-2), typer.substitutions)

    assert Ok(t.Union([#("Log", t.Binary)], None)) = get_sub_type(typed, typer, [1])
    assert Ok(t.Function(t.Union([#("Log", t.Binary)], None), t.Unbound(-1), _)) = get_sub_type(typed, typer, [0])
    
    // test that you can start efect with generic function, probably don't want to support this but checks out in the model
}

pub fn bound_effect_literal_test() {
    let source = e.call(e.variable("raise"), e.tagged("Log", e.binary("hello")))
    // I think unbound -2 is effects in the rest of the continuation
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Union([#("Log", t.Function(t.Binary, t.Tuple([]), t.Unbound(-2)))], None), [])

    assert [] = typer.inconsistencies
    assert Ok(t.Tuple([])) = get_type(typed, typer)

    assert Ok(t.Union([#("Log", t.Binary)], None)) = get_sub_type(typed, typer, [1])
    assert Ok(t.Function(t.Union([#("Log", t.Binary)], None), t.Tuple([]), _)) = get_sub_type(typed, typer, [0])    
}

pub fn infering_function_effect_test()  {
    let source = e.function(p.Tuple([]), e.call(e.variable("raise"), e.tagged("Log", e.binary("hello"))))
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

    assert [] = typer.inconsistencies
    assert Ok(t.Function(t.Tuple([]), t.Unbound(return), effects)) = get_type(typed, typer)
    assert t.Union([#("Log", t.Function(t.Binary, t.Unbound(resolve), _))], _) = effects
    assert True = resolve == return
}

pub fn incorrect_effect_raised_test() {
    let source = e.call(e.variable("raise"), e.tagged("Log", e.tuple_([])))
    // I think unbound -2 is effects in the rest of the continuation
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Union([#("Log", t.Function(t.Binary, t.Tuple([]), t.Unbound(-2)))], None), [])

    assert [#([0], typer.UnmatchedTypes(t.Binary, t.Tuple([])))] = typer.inconsistencies
}

pub fn incorrect_effect_returned_test() {
    let source = e.call(e.variable("raise"), e.tagged("Log", e.binary("hello")))
    // I think unbound -2 is effects in the rest of the continuation
    let #(typed, typer) = analysis.infer_effectful(source, t.Binary, t.Union([#("Log", t.Function(t.Binary, t.Tuple([]), t.Unbound(-2)))], None), [])

    assert [#([0], typer.UnmatchedTypes(t.Tuple([]), t.Binary))] = typer.inconsistencies
}

pub fn effect_with_not_a_union_type_test() {
    let source = e.call(e.variable("raise"), e.tuple_([]))
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [])

    assert [#([1], typer.UnmatchedTypes(t.Union(_,_), t.Tuple([])))] = typer.inconsistencies
}

pub fn cant_call_effect_in_pure_env_test() {
    let source = e.call(e.variable("raise"), e.tagged("Log", e.binary("hello")))
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

    // maybe this ends up on the call level i.e. an error at the root
    assert [#([0], typer.UnexpectedFields([#("Log", _)]))] = typer.inconsistencies
}

pub fn mismateched_effect_test() {
    let source = e.tuple_([log(e.binary("hello")), log(e.tuple_([]))])
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [])

    assert [#([1, 0], typer.UnmatchedTypes(expected: t.Binary, given: t.Tuple(elements: [])))] = typer.inconsistencies
}

pub fn mismateched_effect_in_block_test() {
    let source = e.let_(p.Tuple([]), log(e.binary("hello")), log(e.tuple_([])))
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [])

    assert [#([2, 0], typer.UnmatchedTypes(expected: t.Binary, given: t.Tuple(elements: [])))] = typer.inconsistencies
}

// --------------------- Handle Keyword -----------------------------

// // If i stop it doesn't have to be type checked
// (eff, state) => {
//     Log(#(line, cont)) -> {
//         let #(value, state) = cont([])
//         #(value, [line, ..state])
//     }
//     Return(value) -> #(value, [])
// }

// (eff, state) => {
//     Flip(#([], cont)) -> #(append(cont(true), cont(false)), Nil)
//     Return(value) -> #([value], Nil)
// }


// ```js
// function foo() {
//     let a = []
//     effect({Log: "message"}).cont([] => {
//     let b = []
//     if b == true {
//         return effect({Log: "world"})
//     } else {

//     }.cont(([]) => {
//     b + 1
//     })
//     })
// }
// ```

// // Shallow vs deep handlers are possible
// // handle(handler)(initial)(func)(arg hmmm)

// // https://www.youtube.com/watch?v=3Ltgkjpme-Y freer monads
// // linked from shallow vs deep https://homepages.inf.ed.ac.uk/slindley/papers/shallow-extended.pdf
// // Frank has shallow

pub fn not_a_function_handler_test() {
    let source = e.call(e.variable("catch"), e.binary("yo!"))
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

    // maybe this ends up on the call level i.e. an error at the root
    assert [#([1], typer.UnmatchedTypes(t.Function(_,_,_), t.Binary))] = typer.inconsistencies
}

// Test missing pure

pub fn infer_hole_type_for_handler_test() {
    let handler = e.function(p.Variable("eff"), e.case_(e.variable("eff"),[
        #("Pure", p.Tuple([]), e.tuple_([e.tuple_([]), e.binary("foo")])),
        #("Foo", p.Tuple(["v", "k"]), e.tuple_([e.variable("v"), e.call(e.variable("k"), e.binary("read"))]))
    ]))
    let source = e.call(e.variable("catch"), handler)
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

    typer.inconsistencies
    |> io.debug
    io.debug("===================")
    assert Ok(t.Function(computation, t.Function(arg, ret, eff), t.Union([], None))) = get_type(typed, typer)
    // This should have the effects
    computation
    |> io.debug
    arg
    |> io.debug
    ret
    |> io.debug
    // eff should be empty at theis time
    eff
    |> io.debug


    todo("stop here")
    // let source = e.call(e.call(
    //     e.call(e.variable("catch"), handler), 
    //     e.function(p.variable("a"), e.call(e.variable("raise"), e.tagged("Foo", e.variable("a"))))
    // ), e.record([]))
    // let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

    // // maybe this ends up on the call level i.e. an error at the root
    // // assert [#(hole_path, typer.Warning(_))] = 
    // typer.inconsistencies
    // |> io.debug
    // get_type(typed, typer)
    // |> io.debug
    // assert Ok(t.Function(effect_variants, proper_return, _)) = get_sub_type(typed, typer, [0,0,1])
    // |> io.debug
}

pub fn handle_logs_in_collection_test() {
    let source = e.call(e.variable("catch"), collect_logs())
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.empty, [])

    // maybe this ends up on the call level i.e. an error at the root
    assert [] = typer.inconsistencies
    |> io.debug
    // assert Ok(t.Unbound(-1)) = 
    assert Ok(t) =get_type(typed, typer)
    // |> io.debug
    t
    |> type_info.to_string
    todo("more")
}



// --------------------- LOG functions ------------------------------

const log_fn = #("log", polytype.Polytype([1], t.Function(t.Binary, t.Tuple([]), t.Union([#("Log", t.Binary)], Some(1)))))
const abort_fn = #("abort", polytype.Polytype([1], t.Function(t.Tuple([]), t.Tuple([]), t.Union([#("Abort", t.Tuple([]))], Some(1)))))

pub fn single_effect_test() {
    let source = e.call(e.variable("log"), e.binary("my log"))

    // I think effect type should just be union
    // open effects space
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [log_fn])
    assert t.Union([#("Log", t.Binary)], Some(_)) = t.resolve(t.Unbound(-2), typer.substitutions)
    assert [] = typer.inconsistencies

    // unbound term of effect
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Union([#("Log", t.Unbound(-2))], None), [log_fn])
    assert t.Binary = t.resolve(t.Unbound(-2), typer.substitutions)
    assert [] = typer.inconsistencies

    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Union([#("Log", t.Binary)], None), [log_fn])
    assert [] = typer.inconsistencies

    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Union([#("Log", t.Tuple([]))], None), [log_fn])
    assert [#([0], typer.UnmatchedTypes(t.Tuple([]), t.Binary))] = typer.inconsistencies

    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.empty, [log_fn])
    assert [#([0], typer.UnexpectedFields([#("Log", t.Binary)]))] = typer.inconsistencies

    // function test
    let source = e.function(p.Tuple([]), source)
    // Potentially open is a better name to t.empty
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.empty, [log_fn])
    assert [] = typer.inconsistencies
    assert t.Function(t.Tuple([]), t.Tuple([]), effect) = t.resolve(t.Unbound(-1), typer.substitutions)
    assert t.Union([#("Log", t.Binary)], Some(_)) = effect
}

pub fn multiple_call_effect_test() {
    let source = e.call(e.variable("abort"), e.call(e.variable("log"), e.binary("my log")))

    // I think effect type should just be union
    // open effects space
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [log_fn, abort_fn])
    assert [] = typer.inconsistencies
    assert t.Union([#("Abort", t.Tuple([])), #("Log", t.Binary)], Some(_)) = t.resolve(t.Union([], Some(-2)), typer.substitutions)

    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Union([#("Log", t.Tuple([]))], None), [log_fn, abort_fn])
    assert [
        #([1, 0], typer.UnmatchedTypes(t.Tuple([]), t.Binary)),
        #([0], typer.UnexpectedFields([#("Abort", t.Tuple([]))])),        
    ] = typer.inconsistencies

        // function test
    let source = e.function(p.Tuple([]), source)
    // Potentially open is a better name to t.empty
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.empty, [log_fn, abort_fn])
    assert [] = typer.inconsistencies
    assert t.Function(t.Tuple([]), t.Tuple([]), effect) = t.resolve(t.Unbound(-1), typer.substitutions)
    assert t.Union([#("Abort", t.Tuple([])), #("Log", t.Binary)], Some(_)) = effect
}

pub fn multiple_let_effect_test() {
    let source = e.let_(p.Tuple([]), e.call(e.variable("log"), e.binary("my log")),
        e.call(e.variable("abort"), e.tuple_([]))
    )
    
    // I think effect type should just be union
    // open effects space
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Unbound(-2), [log_fn, abort_fn])
    assert [] = typer.inconsistencies
    assert t.Union([#("Log", t.Binary), #("Abort", t.Tuple([]))], Some(_)) = t.resolve(t.Union([], Some(-2)), typer.substitutions)

    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.Union([#("Log", t.Tuple([]))], None), [log_fn, abort_fn])
    assert [
        #([2, 0], typer.UnexpectedFields([#("Abort", t.Tuple([]))])),        
        #([1, 0], typer.UnmatchedTypes(t.Tuple([]), t.Binary)),
    ] = typer.inconsistencies

    let source = e.function(p.Tuple([]), source)
    // Potentially open is a better name to t.empty
    let #(typed, typer) = analysis.infer_effectful(source, t.Unbound(-1), t.empty, [log_fn, abort_fn])
    assert [] = typer.inconsistencies
    assert t.Function(t.Tuple([]), t.Tuple([]), effect) = t.resolve(t.Unbound(-1), typer.substitutions)
    assert t.Union([#("Log", t.Binary), #("Abort", t.Tuple([]))], Some(_)) = effect
}
