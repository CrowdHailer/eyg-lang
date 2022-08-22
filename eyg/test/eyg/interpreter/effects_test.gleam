import gleam/io
import gleam/map
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter as r
import eyg/interpreter/tail_call



// TODO type checking with effects
// TODO type checking with envs
// pub fn handle(eff)  {
//     io.debug(eff)
//     case eff {
//         r.Effect("Log", v, then)  -> todo
//         _ -> todo
//     }
//     // {
//     //     Foo(_ => bob)
//     // }
// }
// let handler [effect, k] => match effect {
//     Log message => (string append, k([]))
//  }

// TODO make computation be a function i.e. a computation to be run later i.e. [] -> thing
fn handle(handler, computation) { 
    todo("this one")
    // match on inside

    // Return WithHandler type, this is why fn gets made into thunk in unison because returning early means dont find handler
}

fn log(term) { 
    e.call(e.variable("effect"), e.tagged("Log", term))
 }
fn effect(term) { 
    case term {
        r.Tagged(name, value) -> Ok(r.Effect(name, value, fn(_) { todo("placeholder for continuation")}))
        _ -> Error("not a good effect")
    }
}

fn env() { 
    map.new()
    |> map.insert("effect", r.BuiltinFn(effect))
    |> map.insert("handle", r.BuiltinFn(fn(x) {Ok(r.BuiltinFn(handle(x,_)))}))
}

pub fn unhandled_effect_test()  {
    let source = e.let_(p.Variable("a"), log(e.binary("hello")), e.let_(p.Variable("b"), log(e.binary("world")), e.tuple_([e.variable("a"), e.variable("b")])))


    // assert Ok(r.Effect("Log", r.Binary("hello"), cont)) = tail_call.eval(source, env())
    // |> io.debug
    // assert Ok(r.Effect("Log", r.Binary("world"), cont)) = cont(r.Tuple([]))
    // assert Ok(r.Tuple([r.Tuple([]), r.Tuple([])])) = cont(r.Tuple([]))

    let handler = e.function(p.Tuple(["value", "then"]), e.tuple_([]))
    let handled = e.call(e.call(e.variable("handle"), handler), source)
    assert Ok(r.Effect("Log", r.Binary("hello"), cont)) = tail_call.eval(handled, env())
    |> io.debug
    todo("hooo")
}

// statefull pulling of value