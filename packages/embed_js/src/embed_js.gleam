//// The Gleam half of `eyg.mjs`, EYG for JavaScript hosts. A session is a shell
//// with the packages loaded from a hub. Values cross as JSON text, which
//// `eyg.mjs` turns into plain JavaScript values.

import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/embed/browser
import eyg/embed/json
import eyg/embed/shell
import eyg/hub/cache.{type Cache}
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/parser
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/json as gleam_json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import ogre/origin.{type Origin}

pub type Session {
  Session(
    shell: shell.Shell,
    cache: Cache(shell.Span),
    hub: Option(Origin),
    effects: shell.Effects,
  )
}

pub type Run {
  Run(
    session: Session,
    json: Option(String),
    display: Option(String),
    error: Option(String),
  )
}

/// `effects` is `{Label: {lift: T, lower: T}}`, `hub` an origin or "".
pub fn create(effects: Dynamic, hub: String) -> Result(Session, String) {
  use effects <- result.try(
    decode.run(effects, json.effects_decoder())
    |> result.replace_error(
      "effects are not described as {Label: {lift, lower}}",
    ),
  )
  use hub <- result.map(case hub {
    "" -> Ok(None)
    hub ->
      origin.from_string(hub)
      |> result.map(Some)
      |> result.replace_error("the hub is not an origin")
  })
  // Pull only when a reference needs a release; pure runs need no hub traffic.
  let cache = cache.empty()
  Session(shell: resolving(shell.new(effects), cache), cache:, hub:, effects:)
}

fn resolving(shell, cache) {
  shell.with_references(shell, fn(reference) {
    cache.get_reference(cache, reference)
    |> result.map(fn(module) { shell.Module(module.value, module.type_) })
  })
}

/// Load the packages the code refers to, if the session has a hub.
pub fn load(session: Session, code: String) -> Promise(Session) {
  case session.hub, parser.all_from_string(code) {
    Some(hub), Ok(source) -> {
      use cache <- promise.map(
        cache.load(
          session.cache,
          source,
          hub,
          browser.fetch,
          browser.hash,
          fn(_) { #(0, 0) },
        )(promise.resolve),
      )
      Session(..session, shell: resolving(session.shell, cache), cache:)
    }
    _, _ -> promise.resolve(session)
  }
}

/// Put a module in scope, after loading what it refers to.
pub fn with_module(
  session: Session,
  name: String,
  code: String,
) -> Promise(Result(Session, String)) {
  use session <- promise.map(load(session, code))
  use shell <- result.map(shell.with_module(session.shell, name, code))
  Session(..session, shell:)
}

/// A string field of a module in scope, such as its readme.
pub fn text(session: Session, name: String, field: String) -> String {
  shell.text(session.shell, name, field)
}

/// Run code with `handle(label, input_json)` answering effects in JSON.
pub fn run(
  session: Session,
  code: String,
  handle: fn(String, String) -> String,
) -> Run {
  shell.run(session.shell, code, Nil, fn(state, label, lift) {
    use input <- result.try(encode(lift))
    reply(session, label, handle(label, input)) |> result.map(pair(state, _))
  })
  |> finish(session)
}

/// Load what the code refers to, then run it with a handler that may wait.
pub fn run_async(
  session: Session,
  code: String,
  handle: fn(String, String) -> Promise(String),
) -> Promise(Run) {
  use session <- promise.await(load(session, code))
  shell.run_async(session.shell, code, Nil, fn(state, label, lift) {
    case encode(lift) {
      Ok(input) -> {
        use output <- promise.map(handle(label, input))
        reply(session, label, output) |> result.map(pair(state, _))
      }
      Error(reason) -> promise.resolve(Error(reason))
    }
  })
  |> promise.map(finish(_, session))
}

fn pair(a, b) {
  #(a, b)
}

fn encode(value) {
  json.to_json(value) |> result.map(gleam_json.to_string)
}

// A reply must be JSON of the type the effect was declared with.
fn reply(
  session: Session,
  label,
  output,
) -> Result(state.Value(shell.Span), String) {
  let lower =
    list.key_find(session.effects, label)
    |> result.map(fn(types: #(binding.Mono, binding.Mono)) { types.1 })
  case lower, gleam_json.parse(output, json.value_decoder()) {
    Ok(lower), Ok(value) ->
      case json.conforms(value, lower) {
        True -> Ok(value)
        False ->
          Error("the reply " <> output <> " is not a " <> debug.mono(lower))
      }
    Ok(_), Error(_) -> Error("the reply " <> output <> " is not a value")
    Error(Nil), _ -> Error("no effect " <> label)
  }
}

fn finish(run: shell.Run(Nil), session: Session) -> Run {
  let shell.Run(shell:, outcome:, ..) = run
  let session = Session(..session, shell:)
  case outcome {
    shell.Returned(Some(value)) ->
      Run(
        session,
        encode(value) |> option.from_result,
        Some(simple_debug.inspect(value)),
        None,
      )
    shell.Returned(None) -> Run(session, None, None, None)
    other -> Run(session, None, None, Some(shell.report([], other)))
  }
}
