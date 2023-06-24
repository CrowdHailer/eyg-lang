import gleam/io
import gleam/map
import gleam/string
import gleam/javascript/array
import plinth/browser/document
import easel/embed
import eygir/decode
import harness/ffi/cast
import eyg/runtime/interpreter as r
import harness/ffi/env
import harness/stdlib
import plinth/browser/console
import eyg/analysis/jm/type_ as t

pub fn run() {
  let containers = document.query_selector_all("[data-ready]")
  // This is a the location for a style of qwikloader, add global handlers and then look up attributes.
  // i.e. data-click.
  // How do i handle adding state to something being active i.e. in memory value of state
  array.map(containers, start)
}

fn start(container) {
  let assert Ok(program) = document.dataset_get(container, "ready")
  case program {
    "editor" -> embed.fullscreen(container)
    "snippet" -> embed.snippet(container)
    "applet" -> applet(container)
    _ -> {
      io.debug(#("unknown program", program))
      Nil
    }
  }
}

fn applet(root) {
  case document.query_selector(root, "script[type=\"application/eygir\"]") {
    Ok(script) -> {
      console.log(script)
      let assert Ok(source) =
        decode.from_json(string.replace(document.inner_text(script), "\\/", "/"))
      {
        let assert r.Value(term) = r.eval(source, stdlib.env(), r.Value)
        use func <- cast.field("func", cast.any, term)
        // run func arg can be a thing
        // weird return wrapping for cast
        // stdlib only builtins used
        let builtins = stdlib.env().builtins
        let handlers =
          map.new()
          // |> map.insert("Alert", handler)
          |> map.insert("Log", console_log().2)
        let assert r.Value(page) =
          r.handle(
            r.eval_call(func, r.unit, builtins, r.Value),
            builtins,
            handlers,
          )
        use initial <- cast.string(page)
        document.set_html(root, initial)
        initial

        r.Value(func)
      }
      Nil
    }
    Error(Nil) -> {
      io.debug("no applet code")
      Nil
    }
  }
}

pub fn console_log() {
  #(
    t.String,
    t.unit,
    fn(message, k) {
      use message <- cast.string(message)
      console.log(message)
      r.continue(k, r.unit)
    },
  )
}
