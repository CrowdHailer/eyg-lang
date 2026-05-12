//// Module that handles executing an EYG program in the browser environment
//// It handles both effects and caching data for packages, releases and modules from the hub.
//// I have tried splitting this code into separate effect handling and hub client/cache modules but it has not worked
//// Running effectful code requires access to modules, evaluating a module when it is loaded requires a runner.
//// 
//// This modules goal is to be used across all SPA's on the EYG website.
//// It should also be a useful component in any compiled script tag that allows EYG components to be embedded in other places.
//// 
//// Running in a SPA means that all side effects need to be handled by returning effects
//// and resume functions to transform the effect result into something that can be handled by this context module
//// 
//// This module is not parameterised over an arbitrary set of effects.
//// Previously implementations tried this but because of the SPA environment this is hard to do.
//// Some effects are synchronous some are not.
//// Returning a thunk for each effect was not a good interface as the thunk was not introspectable.
////  so rendering what effect was inprogress required the string label for the effect to be passed around.
//// 
//// This module creates an in memory cache of the type and value of all modules.
//// If caching of modules in the browser file system is needed it will also be handled here.

import eyg/analysis/type_/binding
import eyg/hub/cache
import eyg/hub/client
import eyg/interpreter/break
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/http/request
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import morph/buffer
import multiformats/cid/v1
import ogre/operation
import ogre/origin
import touch_grass/copy
import touch_grass/decode_json
import touch_grass/fetch
import touch_grass/flip
import touch_grass/now
import touch_grass/paste
import touch_grass/print
import touch_grass/prompt
import touch_grass/random

// import touch_grass/sleep
import untethered/ledger/schema
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

pub type Effect =
  #(String, #(Value, Value))

/// Context is global over all the runs in a page,
/// It contains the in memory cache or tokens and values for references
pub type Context(m) {
  Context(
    hub_origin: origin.Origin,
    counter: Int,
    cache: cache.Cache(Meta),
    authentiction: Dict(harness.Service, String),
    connecting: List(#(Int, harness.Service, operation.Operation(BitArray))),
    handled: fn(Int, Value) -> m,
    connect_completed: fn(harness.Service, Result(String, String)) -> m,
    module_lookup_completed: fn(v1.Cid, Result(ir.Node(Nil), String)) -> m,
    pull_packages_completed: fn(Result(List(schema.ArchivedEntry), String)) -> m,
  )
}

pub fn empty(
  hub_origin,
  handled,
  connect_completed,
  module_lookup_completed,
  pull_packages_completed,
) {
  Context(
    hub_origin:,
    counter: 0,
    cache: cache.empty(),
    authentiction: dict.new(),
    connecting: [],
    handled:,
    connect_completed:,
    module_lookup_completed:,
    pull_packages_completed:,
  )
}

fn token(context: Context(m), service: harness.Service) -> Result(String, Nil) {
  let Context(authentiction:, ..) = context
  dict.get(authentiction, service)
}

pub type Run(t) {
  Concluded(t)
  Exception(state.Reason(Meta))
  Aborted(String)
  // Can't rely on just the debug state as we need the effect counter.
  Handling(task_id: Int, env: state.Env(Meta), k: state.Stack(Meta))
  // waiting for a dependency.
  Pending(dep: cache.Dependency, env: state.Env(Meta), k: state.Stack(Meta))
}

fn handled(task_id, cast, context: Context(_)) {
  fn(r) { context.handled(task_id, cast(r)) }
}

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
  let #(return, cache) = cache.loop(return, context.cache, resume)
  let context = Context(..context, cache:)
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
        Ok(harness.Now) ->
          now.encode(now.sync())
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
        // Ok(harness.Sleep(max)) -> todo
        // sleep.encode(sleep.sync(max))
        // |> resume(env, k)
        // |> loop(context, resume)
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
        Error(reason) -> #(Exception(reason), context, [])
      }
    }
    Error(#(break.UndefinedReference(cid), _meta, env, k)) ->
      case cache.module(context.cache, cid) {
        cache.Available(cache.Module(value:, ..)) ->
          value
          |> resume(env, k)
          |> loop(context, resume)
        cache.Unknown -> #(Pending(cache.Content(cid), env:, k:), context, [])
        cache.Unavailable(reason) -> #(Exception(reason), context, [])
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
    Error(_) ->
      panic as "this needs to auto return a done message of network error"
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

pub fn pull(context: Context(m)) {
  let cache = cache.pull(context.cache)
  Context(..context, cache:)
}

/// Ensure all of the provided cids are enqued to be fetched.
/// Use `flush` to get the external effect.
pub fn fetch_all(cids: List(v1.Cid), context: Context(m)) -> Context(m) {
  let cache = list.fold(cids, context.cache, cache.fetch)
  Context(..context, cache:)
}

/// A map of the poly types for each pulled module.
/// Use this map in type inference for your program
pub fn module_types(context: Context(m)) -> Dict(v1.Cid, binding.Poly) {
  cache.types(context.cache)
}

/// Create the browser effects required to pull pending modules and package update.
pub fn flush(context: Context(m)) -> #(Context(m), List(browser.Effect(m))) {
  let Context(cache:, hub_origin:, ..) = context
  let #(cache, effects) = cache.flush(cache)
  let context = Context(..context, cache:)
  let effects =
    list.map(effects, fn(effect) {
      case effect {
        cache.FetchModule(cid) ->
          fetch_module(cid, hub_origin, context.module_lookup_completed)
        cache.PullPackages(offset:) ->
          pull_packages(offset, hub_origin, context.pull_packages_completed)
      }
    })
  #(context, effects)
}

/// The browser effect to fetch a module
fn fetch_module(
  cid: v1.Cid,
  hub_origin: origin.Origin,
  module_lookup_completed: fn(v1.Cid, Result(ir.Node(Nil), String)) -> m,
) -> browser.Effect(m) {
  let operation = client.get_module(cid)
  let request = operation.to_request(operation, hub_origin)
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
    module_lookup_completed(cid, result)
  })
}

fn pull_packages(since, hub_origin, pull_packages_completed) {
  let request =
    client.pull_packages(
      schema.PullParameters(since:, limit: 1000, entities: []),
    )
    |> operation.to_request(hub_origin)
  browser.Fetch(request, fn(result) {
    let result = case result {
      Ok(response) ->
        case client.pull_packages_response(response) {
          Ok(schema.PullResponse(entries:)) -> Ok(entries)

          Error(_) -> Error("bad module lookup")
        }
      Error(reason) -> Error(string.inspect(reason))
    }
    pull_packages_completed(result)
  })
}

pub fn get_module_completed(
  context: Context(m),
  cid: v1.Cid,
  result: Result(ir.Node(_), String),
) -> #(Context(m), List(cache.Resolution(Meta))) {
  let result = result.map(result, ir.map_annotation(_, fn(_) { [] }))
  let #(cache, resolutions) = cache.fetched(context.cache, cid, result)
  #(Context(..context, cache:), resolutions)
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

pub type Previous {
  Previous(
    value: Option(state.Value(List(Int))),
    effects: List(Effect),
    buffer: buffer.Buffer,
  )
}
