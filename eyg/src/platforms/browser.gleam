import gleam/dict
import gleam/io
import gleam/list
import eygir/decode
import old_plinth/browser/window
import old_plinth/browser/document
import eyg/runtime/interpreter as r
import eyg/analysis/typ as t
import harness/effect
import harness/stdlib
import gleam/javascript/array
import gleam/javascript/promise
import old_plinth/javascript/promisex
import plinth/javascript/console
import harness/ffi/cast
import harness/ffi/env
import eygir/expression as e

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
  case decode.from_json(window.decode_uri(raw)) {
    Ok(continuation) -> {
      // io.debug(continuation)
      let env = r.Env(scope: [], builtins: stdlib.lib().1)
      // let k = Some(r.Stack(r.CallWith(r.Record([]), [], env), None))
      promise.map(
        // ,
        r.eval_async(
          continuation,
          env,
          r.Stack(
            r.CallWith(r.Record([]), [], env),
            r.WillRenameAsDone(handlers().1),
          ),
        ),
        io.debug,
      )
      // todo as "real"
      Nil
    }
    // case r.run(continuation, stdlib.env(), r.Record([]), handlers().1) {
    //   Ok(_) -> Nil
    //   err -> {
    //     io.debug(#("return", stdlib.env(), err))
    //     Nil
    //   }
    // }
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
      case decode.from_json(window.decode_uri(document.inner_text(el))) {
        Ok(continuation) ->
          case
            r.eval(
              continuation,
              stdlib.env(),
              r.Stack(
                r.CallWith(r.Record([]), [], stdlib.env()),
                r.WillRenameAsDone(handlers().1),
              ),
            )
          {
            r.Value(_) -> Nil
            err -> {
              io.debug(#("return", stdlib.env(), err))
              Nil
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
        case decode.from_json(window.decode_uri(document.inner_text(el))) {
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
  #(
    t.Str,
    t.unit,
    fn(page, k) {
      let env = env.empty()
      let rev = []
      let assert r.Str(page) = page
      case document.query_selector(document.document(), "#app") {
        Ok(element) -> document.set_html(element, page)
        _ ->
          panic as "could not render as no app element found, the reference to the app element should exist from start time and not be checked on every render"
      }

      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

pub fn async() {
  #(
    t.unit,
    t.unit,
    fn(exec, k) {
      let env = stdlib.env()
      let rev = []
      let #(_, extrinsic) =
        handlers()
        |> effect.extend("Await", effect.await())
      // always needs to be executed later so make wrapped as promise from the start
      let promise =
        promisex.wait(0)
        |> promise.await(fn(_: Nil) {
          let ret =
            r.eval_call(exec, r.unit, env, r.WillRenameAsDone(extrinsic))
          r.flatten_promise(ret)
        })
        |> promise.map(fn(result) {
          case result {
            Ok(term) -> term
            Error(#(reason, _path, _env)) -> {
              // has all the path and env in cant' debug
              console.log(r.reason_to_string(reason))
              panic("this shouldn't fail")
            }
          }
        })

      r.prim(r.Value(r.Promise(promise)), rev, env, k)
    },
  )
}

// maybe on click is a better abstraction
// maybe not as puts more in the platform
// maybe global window or single global ref is a good effect
// Write up how passing the handlers gets to choose run context
// i.e. here the click has async but not await
// single extrinsic for listen is a good idea because internally we can build event handlers for on click etc
// need key value for qwik style continuations on the click
fn listen() {
  #(
    t.unit,
    t.unit,
    fn(sub, k) {
      let env = env.empty()
      let rev = []
      use event <- cast.require(
        cast.field("event", cast.string, sub),
        rev,
        env,
        k,
      )
      use handle <- cast.require(
        cast.field("handler", cast.any, sub),
        rev,
        env,
        k,
      )

      let env = stdlib.env()
      let #(_, extrinsic) = handlers()

      window.add_event_listener(event, fn(_) {
        let ret =
          r.eval_call(handle, r.unit, env, r.WillRenameAsDone(extrinsic))
        io.debug(ret)
        Nil
      })
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

fn location_search() {
  #(
    t.unit,
    t.unit,
    fn(_, k) {
      let env = env.empty()
      let rev = []
      let value = case window.location_search() {
        Ok(str) -> r.ok(r.Str(str))
        Error(_) -> r.error(r.unit)
      }

      r.prim(r.Value(value), rev, env, k)
    },
  )
}

// different to listen because replaces handler

fn on_click() {
  #(
    t.unit,
    t.unit,
    fn(handle, k) {
      let env = stdlib.env()
      let rev = []
      let #(_, extrinsic) = handlers()

      document.on_click(fn(arg) {
        let arg = window.decode_uri(arg)
        let assert Ok(arg) = decode.from_json(arg)

        do_handle(arg, handle, env, extrinsic)
      })
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

fn on_keydown() {
  #(
    t.unit,
    t.unit,
    fn(handle, k) {
      let env = stdlib.env()
      let rev = []
      let #(_, extrinsic) = handlers()

      document.on_keydown(fn(k) { do_handle(e.Str(k), handle, env, extrinsic) })
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

fn on_change() {
  #(
    t.unit,
    t.unit,
    fn(handle, k) {
      let env = stdlib.env()
      let rev = []
      let #(_, extrinsic) = handlers()

      document.on_change(fn(k) { do_handle(e.Str(k), handle, env, extrinsic) })
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

fn do_handle(arg, handle, builtins, extrinsic) {
  let assert r.Value(arg) =
    r.eval(arg, stdlib.env(), r.WillRenameAsDone(dict.new()))
  // pass as general term to program arg or fn
  let ret = r.eval_call(handle, arg, builtins, r.WillRenameAsDone(extrinsic))
  case ret {
    r.Value(_) -> Nil
    _ -> {
      io.debug(ret)
      Nil
    }
  }
}
