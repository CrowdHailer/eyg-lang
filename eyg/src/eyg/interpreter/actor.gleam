import gleam/io
import gleam/list
import gleam/map
import gleam/string
import gleam/option.{Some}
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter as r
import eyg/interpreter/tail_call
import eyg/analysis
import eyg/typer
import eyg/codegen/javascript
import eyg/typer/monotype as t

// maybe coroutines is better name and abstraction

// Need to return a continuation that we can step into
fn spawn(loop, continue) {
  // TODO add an env filter step
  Ok(r.Tagged("Spawn", r.Tuple([loop, continue])))
}

fn send(dispatch, continue) {
  assert r.Tuple([pid, message]) = dispatch
  Ok(r.Tagged("Send", r.Tuple([dispatch, continue])))
}

fn done(value) {
  Ok(r.Tagged("Return", value))
}

fn eval(source, pids) {
  let env =
    list.fold(
      pids,
      map.new(),
      fn(env, pair) {
        let #(name, pid) = pair
        map.insert(env, name, pid)
      },
    )
    |> map.insert(
      "harness",
      r.Record([#("debug", r.BuiltinFn(fn(x) { Ok(io.debug(x)) }))]),
    )
    |> map.insert(
      "spawn",
      r.BuiltinFn(fn(loop) { Ok(r.BuiltinFn(spawn(loop, _))) }),
    )
    |> map.insert(
      "send",
      r.BuiltinFn(fn(message) { Ok(r.BuiltinFn(send(message, _))) }),
    )
    // TODO wanted to call this return but need to escape keywords or just interpret in client
    // A quote and encode then interpreting would never need escaping
    |> map.insert("done", r.BuiltinFn(done))
    // TODO start using quote and building into the program runtime things like interpreter type checker etc
    |> map.insert("compile", r.BuiltinFn(app))

  tail_call.eval(source, env)
}

// TODO move app function into the eyg program using concat at that top level
pub fn app(term) {
  let program =
    compile_function(term)
    |> string.append("({ui: 'ui', log: 'log', on_keypress: 'on_keypress'})")

  let app =
    string.concat([
      "<html><body></body><script>\n",
      program,
      "\n</script></html>",
    ])
  Ok(r.Binary(app))
}

// TODO compile needs to take a type argument
// Do we actually want to build all the universal apps
// Using JSON and REST was probably Ok with type providers and we need to start from the outside world
// Compilation process and eval needs to be part of the individual mounts where we use each one.

// TODO infer/unify take a Record type of none for the environment takes record type of some for infering
// Need tasks vs actor for the server handling

//  render closed function if i have recursive patterns on records and tuple makes it very easy to only have relevant variables in scope

// TODO quote and test will make a good path to building everything self hosted

// TODO move compile_function out although it's probably part of the standard library
pub fn compile_function(term) {
  assert r.Function(pattern, body, captured, _) = term

  let client_source = e.function(pattern, body)

  // TODO another good use for structural types is moving builting from functions for evaluation to names for rendering here
  // TODO captured should not include empty
  let #(typed, typer) = analysis.infer(client_source, t.Unbound(-1), [])
  let #(typed, typer) = typer.expand_providers(typed, typer, [])
  // Shouldn't need filter just do it at time of variable creation
  let variables =
    list.filter_map(
      typer.inconsistencies,
      fn(inconsistency) {
        case inconsistency {
          #(_, typer.UnknownVariable(v)) -> Ok(v)
          _ -> Error(Nil)
        }
      },
    )
  let env = map.take(captured, variables)

  let program =
    list.map(map.to_list(env), r.render_var)
    |> list.append([javascript.render_to_string(typed, typer)])
    |> string.join("\n")
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
    r.Tagged("Spawn", r.Tuple([loop, continue])) -> {
      let pid = offset + list.length(processes)
      let processes = list.append(processes, [loop])
      eval_call(continue, r.Pid(pid), offset, processes, messages)
    }
    r.Tagged("Send", r.Tuple([dispatch, continue])) -> {
      let messages = list.append(messages, [dispatch])
      eval_call(continue, r.Tuple([]), offset, processes, messages)
    }
    // TODO dynamic is weird and not caught by type sceme
    r.Tagged("Return", value) | value -> Ok(#(value, processes, messages))
  }
  // _ -> {
  //     io.debug(value)
  //     // todo("should always be typed to the above")
  //     value
  // }
}

pub fn run_source(source, global) {
  let #(names, global) = list.unzip(global)
  let pids = list.index_map(names, fn(i, name) { #(name, r.Pid(i)) })
  try #(value, spawned, dispatched) =
    eval_source(source, list.length(global), pids)
  let processes = list.append(global, spawned)
  try processes = deliver_messages(processes, dispatched)
  Ok(#(value, processes))
}

fn deliver_message(processes, message) {
  assert r.Tuple([r.Pid(i), message]) = message
  let pre = list.take(processes, i)
  let [process, ..post] = list.drop(processes, i)
  try #(process, spawned, dispatched) =
    eval_call(process, message, list.length(processes), [], [])
  let processes = list.flatten([pre, [process], post, spawned])
  Ok(#(processes, dispatched))
}

pub fn deliver_messages(processes, messages) {
  case messages {
    [] -> Ok(processes)
    [message, ..rest] -> {
      try #(processes, dispatched) = deliver_message(processes, message)
      // Message delivery is width first
      deliver_messages(processes, list.append(rest, dispatched))
    }
  }
}
