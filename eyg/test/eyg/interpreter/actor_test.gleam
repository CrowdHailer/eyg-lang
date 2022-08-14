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

fn eval(source, pids) { 
    let env = list.fold(pids, map.new(), fn(env, pair){
        let #(name, pid) = pair
        map.insert(env, name, pid)
    })
    |> map.insert("spawn", r.BuiltinFn(fn(loop) { r.BuiltinFn(spawn(loop, _)) }))
    |> map.insert("send", r.BuiltinFn(fn(message) { r.BuiltinFn(send(message, _)) }))
    |> map.insert("return", r.BuiltinFn(return))

    tail_call.eval(source, env)
}

// I think we start with a step and pass continuation to run but we are now duplicating the Done Eff stuff that is in stepwise
// TODO I think we can remove it at that level

pub fn eval_source(source, offset, pids) {
    try value = eval(source, pids)
    do_eval(value, offset, [], [])
}

pub fn eval_call(func, arg, offset, processes, messages) {
    try value = tail_call.eval_call(func, arg)
    do_eval(value, offset, processes, messages)
}

fn do_eval(value, offset, processes, messages) { 
    case value {
        r.Tagged("Return", value) -> Ok(#(value, processes, messages))
        r.Tagged("Spawn", r.Tuple([loop, continue])) -> {
            let pid = offset + list.length(processes)
            let processes = list.append(processes, [loop])
            eval_call(continue, r.Pid(pid), offset, processes, messages)
        }
        r.Tagged("Send", r.Tuple([dispatch, continue])) -> {
            let messages = list.append(messages, [dispatch])
            eval_call(continue, r.Tuple([]), offset, processes, messages)
        }
        _ -> {
            io.debug(value)
            todo("should always be typed to the above")
        }
    }
}

pub fn run_source(source, global)  {
    let #(names, global) = list.unzip(global)
    let pids = list.index_map(names, fn(i, name) { #(name, r.Pid(i))})
    try #(_value, spawned, dispatched) = eval_source(source, list.length(global), pids)
    let processes = list.append(global, spawned)
    deliver_messages(processes, dispatched)
}

fn deliver_message(processes, message) { 
    assert r.Tuple([r.Pid(i), message]) = message
    let pre = list.take(processes, i)
    let [process, ..post] = list.drop(processes, i)
    try #(process, spawned, dispatched) = eval_call(process, message, list.length(processes), [], [])
    let processes = list.flatten([pre, [process], post, spawned])
    Ok(#(processes, dispatched))
}

fn deliver_messages(processes, messages) { 
    case messages {
        [] -> Ok(processes)
        [message, ..rest] -> {
            try #(processes, dispatched) = deliver_message(processes, message)
            // Message delivery is width first
            deliver_messages(processes, list.append(rest, dispatched))
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
    assert Ok(#(value, processes, messages)) = eval_source(source, 0, [])
    assert r.Pid(0) = value
    assert [process] = processes
    assert r.Function(_,_,_,Some("loop")) = process
    assert [message] = messages
    assert r.Tuple([r.Pid(0), r.Binary("Hello")]) = message
}

fn logger(x) {
    io.debug(x)
    r.Tagged("Return", r.BuiltinFn(logger))
}

pub fn logger_process_test()  {
    let source = e.call(e.call(e.variable("send"), e.tuple_([e.variable("logger"), e.binary("My Log line")])), e.function(p.Variable(""), e.tagged("Return",e.binary("sent"))))
    let global = [#("logger", r.BuiltinFn(logger))]
    assert Ok([process]) = run_source(source, global)
    assert True = process == r.BuiltinFn(logger)
}
