import gleam/map
import eyg/interpreter/interpreter as r
import eyg/interpreter/tail_call

fn impl(handler, computation) {     
    Ok(r.BuiltinFn(fn(arg) {
        try r = tail_call.eval_call(computation, arg)
        let arg = case r {
            r.Effect(name, value, cont) -> r.Tagged(name, r.Tuple([value, r.BuiltinFn(cont)]))
            term -> r.Tagged("Return", term)
        }
        tail_call.eval_call(handler, arg)
    }))
}

fn do(effect) { 
    case effect {
        r.Tagged(name, value) -> Ok(r.Effect(name, value, fn(x) { Ok(x) }))
        _ -> Error("not a good effect")
    }
}


fn env() { 
    map.new()
    |> map.insert("do", r.BuiltinFn(do))
    |> map.insert("impl", r.BuiltinFn(fn(handler) {Ok(r.BuiltinFn(impl(handler,_)))}))
}

pub fn eval(source) {
    tail_call.eval(source, env())
}
