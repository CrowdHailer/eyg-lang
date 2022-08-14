import gleam/io
import gleam/list
import gleam/map
import gleam/option.{Some}
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter as r
import eyg/interpreter/tail_call


// maybe coroutines is better name and abstraction

// Need to return a continuation that we can step into
fn spawn(loop, continue) { 
    // TODO add an env filter step
    assert r.Function(pattern, body, env, self) = loop
    let l = r.Fn(pattern, body, env, self)
    assert r.Function(pattern, body, env, self) = continue
    let c = r.Fn(pattern, body, env, self)
    // TODO remove spawn if type checks are good
    r.Spawn(l, c)
    r.Tagged("Spawn", r.Tuple([loop, continue]))
 }
fn send(dispatch, continue){
    assert r.Tuple([pid, message]) = dispatch
    r.Tagged("Send", r.Tuple([dispatch, continue]))
}
fn return(value) { 
    r.Tagged("Return", value)
 }

fn eval(source) { 
    let env = map.new()
    |> map.insert("spawn", r.BuiltinFn(fn(loop) { r.BuiltinFn(spawn(loop, _)) }))
    |> map.insert("send", r.BuiltinFn(fn(message) { r.BuiltinFn(send(message, _)) }))
    |> map.insert("return", r.BuiltinFn(return))
    tail_call.eval(source, env)
}

// I think we start with a step and pass continuation to run but we are now duplicating the Done Eff stuff that is in stepwise
// TODO I think we can remove it at that level


pub fn eval_source(source, processes, messages) {
    try value = eval(source)
    do_eval(value, processes, messages)
}

pub fn eval_call(func, arg, processes, messages) {
    try value = tail_call.eval_call(func, arg)
    do_eval(value, processes, messages)
}

fn do_eval(value, processes, messages) { 
    case value {
        r.Tagged("Return", value) -> Ok(#(value, processes, messages))
        r.Tagged("Spawn", r.Tuple([loop, continue])) -> {
            let pid = list.length(processes)
            let processes = list.append(processes, [loop])
            eval_call(continue, r.Pid(pid), processes, messages)
        }
        r.Tagged("Send", r.Tuple([dispatch, continue])) -> {
            let messages = list.append(messages, [dispatch])
            eval_call(continue, r.Tuple([]), processes, messages)
        }
        _ -> {
            io.debug(value)
            todo("should always be typed to the above")
        }
    }
}

pub fn start_a_process_test()  {
    let loop = e.let_(p.Variable("loop"), e.function(p.Variable("message"), e.variable("loop")), e.variable("loop"))
    let source = e.call(
        e.call(e.variable("spawn"), loop), 
        e.function(p.Variable("pid"),
            e.call(
                e.call(e.variable("send"), e.tuple_([e.variable("pid"), e.binary("Hello")])), 
                e.function(p.Variable(""), 
                    e.call(e.variable("return"), e.variable("pid"))
            )
        )))
    assert Ok(#(value, processes, messages)) = eval_source(source, [], [])
    assert r.Pid(0) = value
    assert [process] = processes
    assert r.Function(_,_,_,Some("loop")) = process
    assert [message] = messages
    assert r.Tuple([r.Pid(0), r.Binary("Hello")]) = message
}

