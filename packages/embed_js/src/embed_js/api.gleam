//// Plain JavaScript shell API. All retained state and host callback routing live here.

import embed_js as session
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/option.{None, Some}
import javascript/mutable_reference as reference
import plinthx/javascript/foreign
import plinthx/javascript/json as native_json

fn object(fields) {
  foreign.object(array.from_list(fields))
}

fn fail(reason) {
  foreign.raise(foreign.error(reason))
}

fn parse(text) {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

fn encode_reply(value) {
  let value = case foreign.is_undefined(value) {
    True -> object([])
    False -> value
  }
  case native_json.stringify(value) {
    Ok(encoded) -> encoded
    Error(reason) -> fail(reason)
  }
}

fn callback(handlers, label, input) {
  case foreign.has_own(handlers, label) {
    False -> fail("no handler for " <> label)
    True -> {
      let handler = foreign.property(handlers, label)
      case foreign.is_function(handler) {
        False -> fail("no callable handler for " <> label)
        True -> foreign.apply(handler, array.from_list([parse(input)]))
      }
    }
  }
}

fn finish(current, run: session.Run) {
  reference.set(current, run.session)
  let fields = case run.json {
    None -> []
    Some(text) -> [#("value", parse(text))]
  }
  let fields = case run.display {
    None -> fields
    Some(text) -> [#("display", dynamic.string(text)), ..fields]
  }
  let fields = case run.error {
    None -> fields
    Some(text) -> [#("error", dynamic.string(text)), ..fields]
  }
  object(fields)
}

fn load_modules(current, modules) {
  case modules {
    [] -> promise.resolve(current)
    [#(name, code), ..rest] -> {
      use loaded <- promise.await(session.with_module(current, name, code))
      case loaded {
        Ok(current) -> load_modules(current, rest)
        Error(reason) -> fail("module " <> name <> ": " <> reason)
      }
    }
  }
}

/// Return a plain object with text, run and runAsync methods for a native host.
pub fn create_shell(options: Dynamic) -> promise.Promise(Dynamic) {
  use _ <- promise.await(promise.resolve(Nil))
  let decoded =
    decode.run(options, {
      use effects <- decode.field("effects", decode.dynamic)
      use hub <- decode.optional_field("hub", "", decode.string)
      use modules <- decode.optional_field(
        "modules",
        dict.new(),
        decode.dict(decode.string, decode.string),
      )
      decode.success(#(effects, hub, dict.to_list(modules)))
    })
  let #(effects, hub, modules) = case decoded {
    Ok(options) -> options
    Error(_) -> fail("expected {effects, optional hub, optional modules}")
  }
  let created = case session.create(effects, hub) {
    Ok(created) -> created
    Error(reason) -> fail(reason)
  }
  use created <- promise.map(load_modules(created, modules))
  let current = reference.new(created)
  let pending = reference.new(0)
  let queue = reference.new(promise.resolve(Nil))
  object([
    #(
      "text",
      foreign.to_dynamic(fn(name, field) {
        let field = case foreign.is_undefined(field) {
          True -> "readme"
          False ->
            case decode.run(field, decode.string) {
              Ok(field) -> field
              Error(_) -> fail("field must be a string")
            }
        }
        session.text(reference.get(current), name, field)
      }),
    ),
    #(
      "run",
      foreign.to_dynamic(fn(code, handlers) {
        case reference.get(pending) > 0 {
          True -> fail("a shell run is already pending")
          False -> Nil
        }
        reference.set(pending, 1)
        let checked =
          foreign.try_apply(
            foreign.to_dynamic(fn() {
              session.run(reference.get(current), code, fn(label, input) {
                let output = callback(handlers, label, input)
                case foreign.is_thenable(output) {
                  True -> fail("use runAsync for a promise-returning handler")
                  False -> encode_reply(output)
                }
              })
              |> finish(current, _)
            }),
            array.from_list([]),
          )
        reference.set(pending, reference.get(pending) - 1)
        case checked {
          Ok(value) -> value
          Error(reason) -> foreign.raise(reason)
        }
      }),
    ),
    #(
      "runAsync",
      foreign.to_dynamic(fn(code, handlers) {
        reference.set(pending, reference.get(pending) + 1)
        let work =
          {
            use _ <- promise.await(reference.get(queue))
            session.run_async(reference.get(current), code, fn(label, input) {
              callback(handlers, label, input)
              |> foreign.to_promise
              |> promise.map(encode_reply)
            })
            |> promise.map(finish(current, _))
          }
          |> promise.map(fn(value) {
            reference.set(pending, reference.get(pending) - 1)
            value
          })
          |> promise.rescue(fn(reason) {
            reference.set(pending, reference.get(pending) - 1)
            foreign.raise(reason)
          })
        reference.set(
          queue,
          work |> promise.map(fn(_) { Nil }) |> promise.rescue(fn(_) { Nil }),
        )
        work
      }),
    ),
  ])
}
