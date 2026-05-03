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
import gleam/http/request
import gleam/list
import gleam/option.{type Option, None, Some}
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
import website/harness/browser
import website/harness/harness
import website/routes/workspace/buffer

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

pub type Effect =
  #(String, #(Value, Value))

/// Context is global over all the runs in a page,
/// It contains the in memory cache or tokens and values for references
pub type Context(m) {
  Context(
    counter: Int,
    modules: Dict(v1.Cid, Value),
    fetching: Dict(v1.Cid, Fetching),
    authentiction: Dict(harness.Service, String),
    connecting: List(#(Int, harness.Service, operation.Operation(BitArray))),
    handled: fn(Int, Value) -> m,
    connect_completed: fn(harness.Service, Result(String, String)) -> m,
    module_lookup_completed: fn(v1.Cid, Result(ir.Node(Nil), String)) -> m,
  )
}

pub type Fetching {
  Requested
  Invalid(state.Reason(Meta))
  NotFetched(String)
  Dependency(module: v1.Cid, env: state.Env(Meta), k: state.Stack(Meta))
}

pub fn empty(handled, connect_completed, module_lookup_completed) {
  Context(
    counter: 0,
    modules: dict.new(),
    fetching: dict.new(),
    authentiction: dict.new(),
    connecting: [],
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

pub type Run(t) {
  Concluded(t)
  Exception(state.Reason(Meta))
  Aborted(String)
  Handling(task_id: Int, env: state.Env(Meta), k: state.Stack(Meta))
  Fetching(module: v1.Cid, env: state.Env(Meta), k: state.Stack(Meta))
}

fn handled(task_id, cast, context: Context(_)) {
  fn(r) { context.handled(task_id, cast(r)) }
}

// TODO as updated from context
// This needs a map function to be simplified
fn handle(effect, env, k, c, context) {
  #(Handling(c, env, k), context, [effect])
}

// This web_cli loop
pub fn loop(
  return: Result(t, _),
  context: Context(m),
  resume: fn(state.Value(Meta), state.Env(Meta), state.Stack(Meta)) ->
    Result(t, state.Debug(Meta)),
) -> #(Run(t), Context(m), List(browser.Effect(m))) {
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
          loop(resume(decode_json.sync(raw), env, k), context, resume)
        Ok(harness.Download(input)) ->
          browser.Download(input, fn() { context.handled(c, v.unit()) })
          |> handle(env, k, c, updated)
        Ok(harness.Fetch(request)) ->
          browser.fetch(request, handled(c, fetch.encode, context))
          |> handle(env, k, c, updated)
        Ok(harness.Flip) ->
          flip.encode(flip.sync())
          |> resume(env, k)
          |> loop(context, resume)
        Ok(harness.Paste) ->
          browser.ReadFromClipboard(handled(c, paste.encode, context))
          |> handle(env, k, c, updated)
        Ok(harness.Print(message)) ->
          print.encode(print.sync(message))
          |> resume(env, k)
          |> loop(context, resume)
        Ok(harness.Prompt(question)) ->
          browser.Prompt(question, handled(c, prompt.encode, context))
          |> handle(env, k, c, updated)
        Ok(harness.Random(max)) ->
          random.encode(random.sync(max))
          |> resume(env, k)
          |> loop(context, resume)
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
              let request = service_request(service, operation, token)
              browser.fetch(request, handled(c, fetch.encode, context))
              |> handle(env, k, c, updated)
            }
            Error(_) -> {
              let connecting =
                list.append(updated.connecting, [#(c, service, operation)])
              let updated = Context(..updated, connecting:)
              #(Handling(c, env, k), updated, [
                browser.Spotless(service, context.connect_completed(service, _)),
              ])
            }
          }
        Error(break) -> #(Exception(break), context, [])
      }
    }
    Error(#(break.UndefinedReference(cid), _meta, env, k)) -> {
      case get_module(context, cid) {
        Found(value) -> loop(resume(value, env, k), context, resume)
        // returns the fetching state the view looksup in the context a fetching state
        NotFound(_reason) -> #(Fetching(cid, env, k), context, [])
        Pending(updated, effects) -> #(Fetching(cid, env, k), updated, effects)
      }
    }
    Error(#(break, _, _, _)) -> #(Exception(break), context, [])
  }
}

pub fn connect_completed(
  context: Context(m),
  service: harness.Service,
  result: Result(String, String),
) -> #(Context(m), List(browser.Effect(m))) {
  case result {
    Ok(token) -> {
      let Context(authentiction:, ..) = context
      let authentiction = dict.insert(authentiction, service, token)
      let #(connecting, effects) =
        service_tasks(context.connecting, service, [], [], token, context)
      let context = Context(..context, connecting:, authentiction:)

      #(context, effects)
    }
    Error(_) -> todo
  }
}

fn service_tasks(tasks, service, acc, effects, token, context) {
  case tasks {
    [] -> #(list.reverse(acc), list.reverse(effects))
    [#(task_id, s, operation), ..rest] if s == service -> {
      let request = service_request(service, operation, token)

      let effect =
        browser.fetch(request, handled(task_id, fetch.encode, context))
      service_tasks(rest, service, acc, [effect, ..effects], token, context)
    }
    [other, ..rest] ->
      service_tasks(rest, service, [other, ..acc], effects, token, context)
  }
}

pub type Lookup(m) {
  Found(Value)
  NotFound(state.Reason(Meta))
  Pending(Context(m), List(browser.Effect(m)))
}

pub fn fetch_all(cids, context) {
  list.fold(cids, #(context, []), fn(acc, cid) {
    let #(context, effects) = acc
    case get_module(context, cid) {
      Found(_) -> acc
      NotFound(_) -> acc
      Pending(context, new) -> #(context, list.append(effects, new))
    }
  })
}

// cache doesn't deal with the errors
pub fn get_module(context: Context(_), cid: v1.Cid) -> Lookup(m) {
  let Context(fetching:, modules:, ..) = context
  case dict.get(modules, cid), dict.get(fetching, cid) {
    Ok(value), _ -> Found(value)
    Error(Nil), Ok(Requested) -> Pending(context, [])
    Error(Nil), Ok(Dependency(..)) -> Pending(context, [])
    Error(Nil), Ok(Invalid(reason)) -> NotFound(reason)
    Error(Nil), Error(Nil) | Error(Nil), Ok(NotFetched(_)) -> {
      let fetching = dict.insert(fetching, cid, Requested)
      let updated = Context(..context, fetching:)

      let operation = client.get_module(cid)
      // TODO configure origin
      let request = operation.to_request(operation, origin.https("eyg.run"))

      let effect =
        browser.Fetch(request, fn(result) {
          let result = case result {
            Ok(response) ->
              case client.get_module_response(response) {
                Ok(Some(source)) -> Ok(source)
                Ok(None) -> Error("no module")
                Error(_) -> Error("bad module lookup")
              }
            Error(reason) -> Error(string.inspect(reason))
          }
          context.module_lookup_completed(cid, result)
        })
      Pending(updated, [effect])
    }
  }
}

pub fn get_module_completed(
  context: Context(m),
  cid: v1.Cid,
  result: Result(ir.Node(_), String),
) -> #(
  Context(m),
  List(#(v1.Cid, Result(state.Value(Meta), state.Reason(Meta)))),
  List(browser.Effect(m)),
) {
  case result {
    Ok(source) -> {
      let source = ir.map_annotation(source, fn(_) { [] })
      let #(run, context, effects) =
        pure_loop(expression.execute(source, []), context)

      case run, effects {
        Concluded(value), [] -> {
          let modules = dict.insert(context.modules, cid, value)
          let fetching = dict.delete(context.fetching, cid)
          let context = Context(..context, modules:, fetching:)
          cascade_dependencies(context, [#(cid, Ok(value))], [], effects)
        }
        Exception(reason), [] -> {
          let fetching = dict.insert(context.fetching, cid, Invalid(reason))
          let context = Context(..context, fetching:)
          cascade_dependencies(context, [#(cid, Error(reason))], [], effects)
        }
        Aborted(_), [] -> panic as "not in the pure loop handler"
        Handling(task_id: _, env: _, k: _), _ -> panic as "not in the pure loop"
        Fetching(module:, env:, k:), effects -> {
          let fetching =
            dict.insert(context.fetching, cid, Dependency(module:, env:, k:))
          let context = Context(..context, fetching:)
          #(context, [], effects)
        }
        _, [_, ..] -> panic as "There should not be effects for concluded runs"
      }
    }
    Error(message) -> {
      let fetching = dict.insert(context.fetching, cid, NotFetched(message))
      let context = Context(..context, fetching:)
      // Dont cascade as these errors are recoverable
      #(context, [], [])
    }
  }
}

fn pure_loop(
  return: Return,
  context: Context(m),
) -> #(Run(_), Context(m), List(browser.Effect(_))) {
  case return {
    Ok(value) -> #(Concluded(value), context, [])

    Error(#(break.UndefinedReference(cid), _meta, env, k)) ->
      case get_module(context, cid) {
        Found(value) -> pure_loop(expression.resume(value, env, k), context)
        // returns the fetching state the view looksup in the context a fetching state
        NotFound(_reason) -> #(Fetching(cid, env, k), context, [])
        Pending(updated, effects) -> #(Fetching(cid, env, k), updated, effects)
      }
    Error(#(break, _, _, _)) -> #(Exception(break), context, [])
  }
}

fn service_request(service, operation, token) {
  let origin = case service {
    harness.DNSimple -> origin.https("api.dnsimple.com")
    harness.GitHub -> origin.https("api.github.com")
    harness.Vimeo -> origin.https("api.vimeo.com")
  }
  operation.to_request(operation, origin)
  |> request.set_header("authorization", "Bearer " <> token)
}

/// Work through a queue of module lookups, includes successes and invalid modules.
fn cascade_dependencies(
  context: Context(m),
  queue: List(#(v1.Cid, Result(Value, state.Reason(Meta)))),
  completed_acc: List(#(v1.Cid, Result(Value, state.Reason(Meta)))),
  effects_acc: List(browser.Effect(m)),
) -> #(
  Context(m),
  List(#(v1.Cid, Result(Value, state.Reason(Meta)))),
  List(browser.Effect(m)),
) {
  case queue {
    [] -> #(context, completed_acc, effects_acc)
    [#(completed_cid, result), ..rest_queue] -> {
      // Partition the `fetching` dictionary to find released dependencies
      let #(released, remaining) =
        dict.fold(
          over: context.fetching,
          from: #([], dict.new()),
          with: fn(acc, fetch_cid, fetch_state) {
            let #(blocked_acc, new_dict) = acc
            case fetch_state {
              // Match if the state is released on the CID that just completed
              Dependency(dep_cid, env, k) if dep_cid == completed_cid -> #(
                [#(fetch_cid, env, k), ..blocked_acc],
                new_dict,
              )
              _ -> #(blocked_acc, dict.insert(new_dict, fetch_cid, fetch_state))
            }
          },
        )

      let context = Context(..context, fetching: remaining)

      // Iterate over the released modules and resume their execution
      let #(updated_context, new_queue, updated_effects) =
        list.fold(
          over: released,
          from: #(context, rest_queue, effects_acc),
          with: fn(acc, wait_info) {
            let #(context, q, effs) = acc
            let #(waiting_cid, env, k) = wait_info

            case result {
              Ok(value) -> {
                // Resume evaluation with the newly resolved dependency
                let #(run, context, eval_effs) =
                  pure_loop(expression.resume(value, env, k), context)

                // TODO type check top  value

                case run {
                  Concluded(val) -> {
                    let modules = dict.insert(context.modules, waiting_cid, val)
                    let context = Context(..context, modules: modules)
                    // Push to the queue to trigger further cascades
                    #(
                      context,
                      [#(waiting_cid, Ok(val)), ..q],
                      list.append(effs, eval_effs),
                    )
                  }
                  Exception(reason) -> {
                    let fetching =
                      dict.insert(
                        context.fetching,
                        waiting_cid,
                        Invalid(reason),
                      )
                    let context = Context(..context, fetching: fetching)
                    // Push the error to cascade failures
                    #(
                      context,
                      [#(waiting_cid, Error(reason)), ..q],
                      list.append(effs, eval_effs),
                    )
                  }
                  Fetching(dep_cid, e, k2) -> {
                    // Park it again if it immediately needs another module
                    let fetching =
                      dict.insert(
                        context.fetching,
                        waiting_cid,
                        Dependency(dep_cid, e, k2),
                      )
                    let context = Context(..context, fetching: fetching)
                    #(context, q, list.append(effs, eval_effs))
                  }
                  _ -> panic as "unexpected run state in pure loop"
                }
              }
              Error(reason) -> {
                // If the dependency failed, the waiting module automatically fails
                let fetching =
                  dict.insert(context.fetching, waiting_cid, Invalid(reason))
                let context = Context(..context, fetching: fetching)
                #(context, [#(waiting_cid, Error(reason)), ..q], effs)
              }
            }
          },
        )

      cascade_dependencies(
        updated_context,
        new_queue,
        [#(completed_cid, result), ..completed_acc],
        updated_effects,
      )
    }
  }
}

pub type Previous {
  Previous(
    value: Option(state.Value(List(Int))),
    effects: List(Effect),
    buffer: buffer.Buffer,
  )
}
