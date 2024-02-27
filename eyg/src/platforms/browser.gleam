import gleam/dict
import gleam/io
import gleam/list
import gleam/result
import eygir/decode
import plinth/javascript/global
import plinth/browser/window
import old_plinth/browser/document
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eyg/runtime/break
import eyg/analysis/typ as t
import harness/effect
import harness/stdlib
import gleam/javascript/array
import gleam/javascript/promise
import gleam/javascript/promisex
import plinth/javascript/console
import eyg/runtime/cast
import eygir/annotated as e

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
  |> effect.extend("Alert", effect.window_alert())
  |> effect.extend("HTTP", effect.http())
  |> effect.extend("Render", render())
  |> effect.extend("Wait", effect.wait())
  |> effect.extend("Await", effect.await())
  |> effect.extend("Async", async())
  |> effect.extend("Listen", listen())
  |> effect.extend("LocationSearch", location_search())
  |> effect.extend("OnClick", on_click())
  |> effect.extend("OnKeyDown", on_keydown())
  // on change is global
  |> effect.extend("OnChange", on_change())
}

// change with reference and then re rendering/ I can use proper diffing a.la. lustre
// want to keep serialize ability of things including events and reference to elements
// 1. listen on global
// 2. trigger on events but pull value
// 3. think about making events better type

// capturing things is too large

pub fn do_run(raw) -> Nil {
  case decode.from_json(global.decode_uri(raw)) {
    Ok(continuation) -> {
      let env = state.Env(scope: [], builtins: stdlib.lib().1)
      let continuation = e.add_meta(continuation, Nil)
      let assert Ok(continuation) = r.execute(continuation, env, handlers().1)
      promise.map(
        r.await(r.resume(continuation, [v.unit], env, handlers().1)),
        io.debug,
      )
      // todo as "real"
      Nil
    }
    Error(reason) -> {
      io.debug(reason)
      Nil
    }
  }
}

pub fn run() {
  let found =
    document.query_selector(
      document.document(),
      "script[type=\"application/eygir.json\"]",
    )
  case found {
    Ok(el) -> {
      do_run(document.inner_text(el))
    }
    Error(Nil) -> old_run()
  }
}

// used in layout.page -> used in dashboard
fn old_run() {
  case
    document.query_selector(
      document.document(),
      "script[type=\"application/eygir\"]",
    )
  {
    Ok(el) ->
      case decode.from_json(global.decode_uri(document.inner_text(el))) {
        Ok(f) -> {
          let env = stdlib.env()
          let f = e.add_meta(f, Nil)
          let assert Ok(f) = r.execute(f, env, handlers().1)
          let ret = r.resume(f, [v.unit], env, handlers().1)
          case ret {
            Ok(_) -> Nil
            err -> {
              io.debug(#("return", stdlib.env(), err))
              Nil
            }
          }
        }

        Error(reason) -> {
          io.debug(reason)
          Nil
        }
      }

    _ -> {
      io.debug("no script to run")

      let elements =
        document.query_selector_all("script[type=\"editor/eygir\"]")
        |> array.to_list()
      list.map(elements, fn(el) {
        case decode.from_json(global.decode_uri(document.inner_text(el))) {
          Ok(c) -> {
            io.debug(c)
            document.insert_after(el, "<p>Nice</p>")
            Nil
          }
          Error(reason) -> {
            io.debug(reason)
            Nil
          }
        }
      })
      Nil
    }
  }
}

fn render() {
  #(t.Str, t.unit, fn(page) {
    let assert v.Str(page) = page
    case document.query_selector(document.document(), "#app") {
      Ok(element) -> document.set_html(element, page)
      _ ->
        panic as "could not render as no app element found, the reference to the app element should exist from start time and not be checked on every render"
    }
    Ok(v.unit)
  })
}

pub fn async() {
  #(t.unit, t.unit, fn(exec) {
    let env = stdlib.env()
    let #(_, extrinsic) =
      handlers()
      |> effect.extend("Await", effect.await())
    // always needs to be executed later so make wrapped as promise from the start
    let promise =
      promisex.wait(0)
      |> promise.await(fn(_: Nil) {
        r.await(r.resume(exec, [v.unit], env, extrinsic))
      })
      |> promise.map(fn(result) {
        case result {
          Ok(term) -> term
          Error(#(reason, _path, _env, _k)) -> {
            // has all the path and env in cant' debug
            console.log(break.reason_to_string(reason))
            panic("this shouldn't fail")
          }
        }
      })

    Ok(v.Promise(promise))
  })
}

// maybe on click is a better abstraction
// maybe not as puts more in the platform
// maybe global window or single global ref is a good effect
// Write up how passing the handlers gets to choose run context
// i.e. here the click has async but not await
// single extrinsic for listen is a good idea because internally we can build event handlers for on click etc
// need key value for qwik style continuations on the click
fn listen() {
  #(t.unit, t.unit, fn(sub) {
    use event <- result.then(cast.field("event", cast.as_string, sub))
    use handle <- result.then(cast.field("handler", cast.any, sub))

    let env = stdlib.env()
    let #(_, extrinsic) = handlers()

    window.add_event_listener(event, fn(_) {
      let ret = r.resume(handle, [v.unit], env, extrinsic)
      io.debug(ret)
      Nil
    })
    Ok(v.unit)
  })
}

fn location_search() {
  #(t.unit, t.unit, fn(_) {
    let value = case window.get_search() {
      Ok(str) -> v.ok(v.Str(str))
      Error(_) -> v.error(v.unit)
    }
    Ok(value)
  })
}

// different to listen because replaces handler

fn on_click() {
  #(t.unit, t.unit, fn(handle) {
    let env = stdlib.env()
    let #(_, extrinsic) = handlers()

    document.on_click(fn(arg) {
      let arg = global.decode_uri(arg)
      let assert Ok(arg) = decode.from_json(arg)

      let arg = e.add_meta(arg, Nil)
      do_handle(arg, handle, env, extrinsic)
    })
    Ok(v.unit)
  })
}

fn on_keydown() {
  #(t.unit, t.unit, fn(handle) {
    let env = stdlib.env()
    let #(_, extrinsic) = handlers()

    document.on_keydown(fn(k) { r.resume(handle, [v.Str(k)], env, extrinsic) })
    Ok(v.unit)
  })
}

fn on_change() {
  #(t.unit, t.unit, fn(handle) {
    let env = stdlib.env()
    let #(_, extrinsic) = handlers()

    document.on_change(fn(k) { r.resume(handle, [v.Str(k)], env, extrinsic) })
    Ok(v.unit)
  })
}

fn do_handle(arg, handle, builtins, extrinsic) {
  let assert Ok(arg) = r.execute(arg, stdlib.env(), dict.new())
  // pass as general term to program arg or fn
  let ret = r.resume(handle, [arg], builtins, extrinsic)
  case ret {
    Ok(_) -> Nil
    _ -> {
      io.debug(ret)
      Nil
    }
  }
}
