import gleam/map
import eyg/interpreter/interpreter as r
import eyg/interpreter/tail_call

fn handle(handler, computation) {     
    Ok(r.BuiltinFn(fn(arg) {
        try r = tail_call.eval_call(computation, arg)
        let arg = case r {
            r.Effect(name, value, cont) -> r.Tagged(name, r.Tuple([value, r.BuiltinFn(cont)]))
            term -> r.Tagged("Pure", term)
        }
        tail_call.eval_call(handler, arg)
    }))
}

fn effect(term) { 
    case term {
        r.Tagged(name, value) -> Ok(r.Effect(name, value, fn(x) { Ok(x)}))
        _ -> Error("not a good effect")
    }
}


fn env() { 
    map.new()
    |> map.insert("effect", r.BuiltinFn(effect))
    |> map.insert("handle", r.BuiltinFn(fn(x) {Ok(r.BuiltinFn(handle(x,_)))}))
}

pub fn eval(source) {
    tail_call.eval(source, env())
}
