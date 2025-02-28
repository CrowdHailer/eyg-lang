import eyg/analysis/typ as t
import eyg/interpreter/cast
import eyg/interpreter/expression as r
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/runtime/break as old_break
import gleam/bit_array
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/result
import harness/effect
import harness/stdlib
import old_plinth/browser/document as old_document
import plinth/browser/document
import plinth/browser/element
import plinth/browser/window
import plinth/javascript/console
import plinth/javascript/global

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
  |> effect.extend("Alert", effect.window_alert())
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
  case dag_json.from_block(bit_array.from_string(global.decode_uri(raw))) {
    Ok(continuation) -> {
      io.debug("needs to handle handlers handlers().1")
      let assert Ok(continuation) = r.execute(continuation, [])
      promise.map(r.await(r.call(continuation, [#(v.unit(), Nil)])), io.debug)
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
  let found = document.query_selector("script[type=\"application/eygir.json\"]")
  case found {
    Ok(el) -> {
      do_run(element.inner_text(el))
    }
    Error(Nil) -> old_run()
  }
}

// used in layout.page -> used in dashboard
fn old_run() {
  case document.query_selector("script[type=\"application/eygir\"]") {
    Ok(el) ->
      case
        dag_json.from_block(
          bit_array.from_string(global.decode_uri(element.inner_text(el))),
        )
      {
        Ok(f) -> {
          io.debug("needs to handle handlers handlers().1")

          let assert Ok(f) = r.execute(f, [])
          let ret = r.call(f, [#(v.unit(), Nil)])
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
        case
          dag_json.from_block(
            bit_array.from_string(global.decode_uri(element.inner_text(el))),
          )
        {
          Ok(c) -> {
            io.debug(c)
            let assert Ok(_) =
              element.insert_adjacent_html(el, element.AfterEnd, "<p>Nice</p>")
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
    let assert v.String(page) = page
    case document.query_selector("#app") {
      Ok(element) -> element.set_inner_html(element, page)
      _ ->
        panic as "could not render as no app element found, the reference to the app element should exist from start time and not be checked on every render"
    }
    Ok(v.unit())
  })
}

pub fn async() {
  #(t.unit, t.unit, fn(exec) {
    let #(_, extrinsic) =
      handlers()
      |> effect.extend("Await", effect.await())
    // always needs to be executed later so make wrapped as promise from the start
    io.debug("needs to handle handlers handlers().1")

    let promise =
      promise.wait(0)
      |> promise.await(fn(_: Nil) { r.await(r.call(exec, [#(v.unit(), Nil)])) })
      |> promise.map(fn(result) {
        case result {
          Ok(term) -> term
          Error(#(reason, _path, _env, _k)) -> {
            // has all the path and env in cant' debug
            console.log(old_break.reason_to_string(reason))
            panic as "this shouldn't fail"
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

    let #(_, extrinsic) = handlers()

    window.add_event_listener(event, fn(_) {
      io.debug("needs to handle handlers extrinsic")

      let ret = r.call(handle, [#(v.unit(), Nil)])
      io.debug(ret)
      Nil
    })
    Ok(v.unit())
  })
}

fn location_search() {
  #(t.unit, t.unit, fn(_) {
    let value = case window.get_search() {
      Ok(str) -> v.ok(v.String(str))
      Error(_) -> v.error(v.unit())
    }
    Ok(value)
  })
}

// different to listen because replaces handler

fn on_click() {
  #(t.unit, t.unit, fn(handle) {
    let env = stdlib.env()
    let #(_, extrinsic) = handlers()

    old_document.on_click(fn(arg) {
      let arg = global.decode_uri(arg)
      let assert Ok(arg) = dag_json.from_block(bit_array.from_string(arg))

      do_handle(arg, handle, env, extrinsic)
    })
    Ok(v.unit())
  })
}

fn on_keydown() {
  #(t.unit, t.unit, fn(handle) {
    let #(_, extrinsic) = handlers()

    io.debug("needs to handle handlers extrinsic")

    old_document.on_keydown(fn(k) {
      let _ = r.call(handle, [#(v.String(k), Nil)])
      Nil
    })
    Ok(v.unit())
  })
}

fn on_change() {
  #(t.unit, t.unit, fn(handle) {
    let #(_, extrinsic) = handlers()

    io.debug("needs to handle handlers extrinsic")

    old_document.on_change(fn(k) {
      let _ = r.call(handle, [#(v.String(k), Nil)])
      Nil
    })
    Ok(v.unit())
  })
}

fn do_handle(arg, handle, builtins, extrinsic) {
  io.debug("needs to handle handlers extrinsic")

  let assert Ok(arg) = r.execute(arg, [])
  // pass as general term to program arg or fn
  let ret = r.call(handle, [#(arg, Nil)])
  case ret {
    Ok(_) -> Nil
    _ -> {
      io.debug(ret)
      Nil
    }
  }
}
