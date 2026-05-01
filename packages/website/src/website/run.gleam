//// could be called execution or execute (like in cli)
//// This handles the common state for executing a program in the browser
//// This works for the web_cli harness but should work for all harnesses on the browser platform.

import eyg/hub/client
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import multiformats/cid/v1
import ogre/operation
import ogre/origin
import touch_grass/copy
import touch_grass/decode_json
import touch_grass/fetch
import touch_grass/flip
import touch_grass/paste
import touch_grass/print
import touch_grass/prompt
import touch_grass/random
import untethered/ledger/client.{NetworkError} as _
import website/harness/browser
import website/harness/harness

// This could be something not called a runner. loop function in this module would reuse it.
// This cant be reused by workspace as the shell keeps history of effects
// if cast takes a list of interfaces we can have runners with a subset of effects
// Normally it is best to copy paste this function
// 
// This loop is tied to this route/app by the return message type
// The return of the effect could be a code return wot need counter but I don't know how you track trace/effect id
// Probably best to fix module lookup first, as well as spotless, where do we cache, but it should be the same as 
// spotless tokens last over different runs
// 
// Follow the elm pattern or the situation where I like midas pass in effect handlers, so we have a on handled
// on fetched
// hub has an API client
// hub DOES NOT have a state/cache or it's own message types
// The whole thing is a reference to the hub in the website
// hub might have a selection of remotes
// hub.module(cid)
// hub.release() -> current status
// hub.get_release -> tasks if invalid needs an error might always have come into existance
// get_release -> it is ok or refreshes, or errors if the hash is wrong
// pending and 
pub type Meta =
  List(Int)

pub type Value =
  state.Value(Meta)

pub type Debug =
  state.Debug(Meta)

pub type Return =
  Result(Value, Debug)

/// Context is global over all the runs in a page,
/// It contains the in memory cache or tokens and values for references
pub type Context(m) {
  Context(
    counter: Int,
    modules: Dict(v1.Cid, Value),
    authentiction: Dict(harness.Service, String),
    tasks: List(#(Int, Task)),
    handled: fn(Int, Value) -> m,
    connect_completed: fn(harness.Service, Result(String, String)) -> m,
    module_lookup_completed: fn(v1.Cid, Result(ir.Node(Nil), String)) -> m,
  )
}

pub fn empty(handled, connect_completed, module_lookup_completed) {
  Context(
    counter: 0,
    modules: dict.new(),
    authentiction: dict.new(),
    tasks: [],
    handled:,
    connect_completed:,
    module_lookup_completed:,
  )
}

pub fn module(context: Context(_), cid: v1.Cid) -> Result(Value, Nil) {
  let Context(modules:, ..) = context
  dict.get(modules, cid)
}

pub fn token(
  context: Context(_),
  service: harness.Service,
) -> Result(String, Nil) {
  let Context(authentiction:, ..) = context
  dict.get(authentiction, service)
}

pub type Run {
  Concluded(Value)
  Exception(state.Reason(Meta))
  Aborted(String)
  Suspended(task_id: Int, env: state.Env(Meta), k: state.Stack(Meta))
}

pub type Task {
  // Effect
  Connect(service: harness.Service, operation: operation.Operation(BitArray))
  Module(cid: v1.Cid)
  // Release that points at a module
}

fn handled(task_id, cast, context: Context(_)) {
  fn(r) { context.handled(task_id, cast(r)) }
}

// TODO as updated from context
// This needs a map function to be simplified
fn handle(effect, env, k, c, context) {
  #(Suspended(c, env, k), context, [effect])
}

// This web_cli loop
pub fn loop(
  return: Return,
  context: Context(m),
) -> #(Run, Context(m), List(browser.Effect(m))) {
  case return {
    Ok(value) -> #(Concluded(value), context, [])
    Error(#(break.UnhandledEffect(label, lift), _meta, env, k)) -> {
      let Context(counter: c, ..) = context
      let updated = Context(..context, counter: c + 1)
      case harness.cast(label, lift) {
        Ok(harness.Abort(reason)) -> #(Aborted(reason), context, [])
        Ok(harness.Alert(message)) ->
          browser.Alert(message, fn() { context.handled(c, v.unit()) })
          |> handle(env, k, c, updated)
        Ok(harness.Copy(text)) ->
          browser.WriteToClipboard(text, handled(c, copy.encode, context))
          |> handle(env, k, c, updated)
        Ok(harness.DecodeJson(raw)) ->
          loop(expression.resume(decode_json.sync(raw), env, k), context)
        Ok(harness.Download(input)) ->
          browser.Download(input, fn() { context.handled(c, v.unit()) })
          |> handle(env, k, c, updated)
        Ok(harness.Fetch(request)) ->
          browser.fetch(request, handled(c, fetch.encode, context))
          |> handle(env, k, c, updated)
        Ok(harness.Flip) ->
          flip.encode(flip.sync())
          |> expression.resume(env, k)
          |> loop(context)
        Ok(harness.Paste) ->
          browser.ReadFromClipboard(handled(c, paste.encode, context))
          |> handle(env, k, c, updated)
        Ok(harness.Print(message)) ->
          print.encode(print.sync(message))
          |> expression.resume(env, k)
          |> loop(context)

        Ok(harness.Prompt(question)) ->
          browser.Prompt(question, handled(c, prompt.encode, context))
          |> handle(env, k, c, updated)
        Ok(harness.Random(max)) ->
          random.encode(random.sync(max))
          |> expression.resume(env, k)
          |> loop(context)
        Ok(harness.Visit(uri)) ->
          browser.Visit(uri:, resume: fn(result) {
            let value = case result {
              Ok(_) -> v.ok(v.unit())
              Error(reason) -> v.error(v.String(reason))
            }
            context.handled(c, value)
          })
          |> handle(env, k, c, updated)
        Ok(harness.Spotless(service:, operation:)) ->
          case token(context, service) {
            Ok(token) -> {
              let request =
                operation.to_request(operation, origin.https("todo.com"))
              browser.fetch(request, handled(c, fetch.encode, context))
              |> handle(env, k, c, updated)
            }
            Error(_) -> {
              let tasks =
                list.append(updated.tasks, [#(c, Connect(service:, operation:))])
              let updated = Context(..updated, tasks:)
              #(Suspended(c, env, k), updated, [
                browser.Spotless(service, context.connect_completed(service, _)),
              ])
            }
          }
        Error(break) -> #(Exception(break), context, [])
      }
    }
    Error(#(break.UndefinedReference(cid), _meta, env, k)) -> {
      case module(context, cid) {
        Ok(value) -> loop(expression.resume(value, env, k), context)
        Error(Nil) -> {
          let #(c, effects) = get_module(context, cid)
          #(Suspended(c, env, k), context, effects)
        }
      }
    }
    Error(#(break, _, _, _)) -> #(Exception(break), context, [])
  }
}

pub fn connect_completed(
  context: Context(m),
  service: harness.Service,
  result: Result(String, a),
) -> #(Context(m), List(browser.Effect(m))) {
  case result {
    Ok(token) -> {
      let Context(authentiction:, ..) = context
      let authentication = dict.insert(authentiction, service, token)
      let #(tasks, effects) =
        service_tasks(context.tasks, service, [], [], context)
      let context = Context(..context, tasks:)

      #(context, effects)
    }
    Error(_) -> todo
  }
}

fn service_tasks(tasks, service, remaining, effects, context) {
  case tasks {
    [] -> #(list.reverse(remaining), list.reverse(effects))
    [#(task_id, Connect(service: s, operation:)), ..rest] if s == service -> {
      let request = operation.to_request(operation, origin.https("todo.com"))

      let effect =
        browser.fetch(request, handled(task_id, fetch.encode, context))
      service_tasks(rest, service, remaining, [effect, ..effects], context)
    }
    [other, ..rest] ->
      service_tasks(rest, service, [other, ..remaining], effects, context)
  }
}

// cache doesn't deal with the errors
fn get_module(context: Context(_), cid: v1.Cid) {
  // If we pass in a runner state, then it needs to be returned every time
  let operation = client.get_module(cid)
  // TODO configure origin
  let request = operation.to_request(operation, origin.https("eyg.run"))
  // Do we want to look up if already looking

  // This is a browser action
  let effect =
    browser.Fetch(request, fn(result) {
      case result {
        Ok(response) ->
          case client.get_module_response(response) {
            Ok(Some(source)) -> context.module_lookup_completed(cid, Ok(source))
            // state arrives but then we need to work with it. update somehting internaly
            // pure_loop(
            //   expression.execute(
            //     source |> tree.map_annotation(fn(_) { [] }),
            //     [],
            //   ),
            // )
            Ok(None) -> todo
            Error(_) -> todo
          }
        Error(reason) -> todo
        //  Error(NetworkError(string.inspect(reason)))
      }
      // |> ModuleFetched(cid, _)
    })
  #(99_999, [effect])
}

fn get_module_completed(context, result) {
  let source = todo
  let #(run, actions) = pure_loop(expression.execute(source, []), context)
  // new state
  case run, actions {
    Concluded(_), [] -> todo
    Exception(_), [] -> todo
    Aborted(_), [] -> todo
    Suspended(task_id:, env:, k:), _ -> todo
    _, [_, ..] -> todo
  }
  // returns task potentially
}

fn pure_loop(
  return: Return,
  context: Context(_),
) -> #(Run, List(browser.Effect(_))) {
  todo
  // case return {
  //   Ok(value) -> #(Concluded(value), [])

  //   Error(#(break.UndefinedReference(cid), _meta, env, k)) -> {
  //     let refs = todo
  //     case dict.get(refs, cid) {
  //       Ok(value) -> pure_loop(expression.resume(value, env, k), context)
  //       Error(Nil) -> #(Fetching(env, k), [get_module(cid)])
  //     }
  //   }
  //   Error(#(break, _, _, _)) -> #(Failed(simple_debug.describe(break)), [])
  // }
}
