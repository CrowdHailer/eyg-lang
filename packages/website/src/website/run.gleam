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
pub type Context {
  Context(
    counter: Int,
    modules: Dict(v1.Cid, Value),
    authentiction: Dict(harness.Service, String),
  )
}

pub fn empty() {
  Context(counter: 0, modules: dict.new(), authentiction: dict.new())
}

pub fn module(context: Context, cid: v1.Cid) -> Result(Value, Nil) {
  let Context(modules:, ..) = context
  dict.get(modules, cid)
}

pub fn token(context: Context, service: harness.Service) -> Result(String, Nil) {
  let Context(authentiction:, ..) = context
  dict.get(authentiction, service)
}

pub type Message {
  Handled(task_id: Int, value: Value)
  SpotlessConnectCompleted(Result(String, String))
  ModuleLookupCompleted(Result(ir.Node(Nil), String))
}

pub type Run {
  Concluded(Value)
  Exception(state.Reason(Meta))
  Aborted(String)
  Suspended(
    task_id: Int,
    pending: Pending,
    env: state.Env(Meta),
    k: state.Stack(Meta),
  )
}

pub type Pending {
  Effect
  Connect(service: harness.Service, operation: operation.Operation(BitArray))
  Module(cid: v1.Cid)
  // Release that points at a module
}

fn handled(task_id, cast) {
  fn(r) { Handled(task_id:, value: cast(r)) }
}

// TODO as updated from context
// This needs a map function to be simplified
fn handle(effect, env, k, c, context) {
  #(Suspended(c, Effect, env, k), context, [effect])
}

// This web_cli loop
pub fn loop(
  return: Return,
  context: Context,
) -> #(Run, Context, List(browser.Effect(Message))) {
  case return {
    Ok(value) -> #(Concluded(value), context, [])
    Error(#(break.UnhandledEffect(label, lift), _meta, env, k)) -> {
      let Context(counter: c, ..) = context
      let updated = Context(..context, counter: c + 1)
      case harness.cast(label, lift) {
        Ok(harness.Abort(reason)) -> #(Aborted(reason), context, [])
        Ok(harness.Alert(message)) ->
          browser.Alert(message, fn() { Handled(c, v.unit()) })
          |> handle(env, k, c, updated)
        Ok(harness.Copy(text)) ->
          browser.WriteToClipboard(text, handled(c, copy.encode))
          |> handle(env, k, c, updated)
        Ok(harness.DecodeJson(raw)) ->
          loop(expression.resume(decode_json.sync(raw), env, k), context)
        Ok(harness.Download(input)) ->
          browser.Download(input, fn() { Handled(c, v.unit()) })
          |> handle(env, k, c, updated)
        Ok(harness.Fetch(request)) ->
          browser.fetch(request, handled(c, fetch.encode))
          |> handle(env, k, c, updated)
        Ok(harness.Flip) ->
          flip.encode(flip.sync())
          |> expression.resume(env, k)
          |> loop(context)
        Ok(harness.Paste) ->
          browser.ReadFromClipboard(handled(c, paste.encode))
          |> handle(env, k, c, updated)
        Ok(harness.Print(message)) ->
          print.encode(print.sync(message))
          |> expression.resume(env, k)
          |> loop(context)

        Ok(harness.Prompt(question)) ->
          browser.Prompt(question, handled(c, prompt.encode))
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
            Handled(c, value)
          })
          |> handle(env, k, c, updated)
        Ok(harness.Spotless(service:, operation:)) ->
          case token(context, service) {
            Ok(token) -> {
              let request =
                operation.to_request(operation, origin.https("todo.com"))
              browser.fetch(request, handled(c, fetch.encode))
              |> handle(env, k, c, updated)
            }
            Error(_) -> {
              #(Suspended(c, Connect(service, operation), env, k), updated, [
                browser.Spotless(service, SpotlessConnectCompleted),
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
          let #(c, effect) = get_module(context, cid)
          #(Suspended(c, Module(cid:), env, k), context, [effect])
        }
      }
    }
    Error(#(break, _, _, _)) -> #(Exception(break), context, [])
  }
}

// cache doesn't deal with the errors
fn get_module(context, cid: v1.Cid) {
  // If we pass in a runner state, then it needs to be returned every time
  let operation = client.get_module(cid)
  // TODO configure origin
  let request = operation.to_request(operation, origin.https("eyg.run"))
  // Do we want to look up if already looking

  // This is a browser action
  browser.Fetch(request, fn(result) {
    case result {
      Ok(response) ->
        case client.get_module_response(response) {
          Ok(Some(source)) -> todo as "has to return just source"
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
      Error(reason) -> Error(NetworkError(string.inspect(reason)))
    }
    |> todo
    // |> ModuleFetched(cid, _)
  })
  todo
}

fn get_module_completed(context, result) {
  let source = todo
  let #(run, actions) = pure_loop(expression.execute(source, []), context)
  // new state
  case run, actions {
    Concluded(_), [] -> todo
    Exception(_), [] -> todo
    Aborted(_), [] -> todo
    Suspended(task_id:, env:, k:, pending:), _ -> todo
    _, [_, ..] -> todo
  }
  // returns task potentially
}

fn pure_loop(
  return: Return,
  context: Context,
) -> #(Run, List(browser.Effect(Message))) {
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
