import gleam/io
import gleam/int
import gleam/list
import gleam/map
import gleam/option.{None}
import gleam/string
import gleam/javascript/array
import gleam/javascript
import old_plinth/browser/document
import easel/embed
import eygir/decode
import harness/ffi/cast
import eyg/runtime/interpreter as r
import harness/ffi/env
import harness/stdlib
import plinth/javascript/console
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
        let env = stdlib.env()
        let rev = []
        let k = None
        let assert r.Value(term) = r.eval(source, env, k)
        use func <- cast.require(
          cast.field("func", cast.any, term),
          rev,
          env,
          k,
        )
        use arg <- cast.require(cast.field("arg", cast.any, term), rev, env, k)
        // run func arg can be a thing
        // weird return wrapping for cast
        // stdlib only builtins used
        let actions = javascript.make_reference([])
        let handlers =
          map.new()
          |> map.insert(
            "Update",
            fn(action, k) {
              let saved = javascript.dereference(actions)
              let id = int.to_string(list.length(saved))
              let saved = [action, ..saved]
              javascript.set_reference(actions, saved)
              r.prim(r.Value(r.Binary(id)), rev, env, k)
            },
          )
          |> map.insert("Log", console_log().2)
        let state = javascript.make_reference(arg)
        let render = fn() {
          let current = javascript.dereference(state)
          let result =
            r.handle(r.eval_call(func, current, env, None), env, handlers)
          let _ = case result {
            r.Value(r.Binary(page)) -> document.set_html(root, page)
            _ -> {
              io.debug(#("unexpected", result))
              panic("nope")
            }
          }
        }

        document.add_event_listener(
          root,
          "click",
          fn(event) {
            case nearest_click_handler(event) {
              Ok(id) -> {
                case
                  list.at(list.reverse(javascript.dereference(actions)), id)
                {
                  Ok(code) -> {
                    // handle effects
                    let current = javascript.dereference(state)
                    // io.debug(javascript.dereference(actions))
                    let assert r.Value(next) =
                      r.eval_call(code, current, env, None)
                    javascript.set_reference(state, next)
                    javascript.set_reference(actions, [])
                    render()
                    Nil
                  }
                  Error(Nil) -> {
                    io.debug("should have been ref")
                    Nil
                  }
                }
                Nil
              }
              Error(Nil) -> Nil
            }
          },
        )
        render()
        r.prim(r.Value(func), rev, env, k)
      }
      Nil
    }
    Error(Nil) -> {
      io.debug("no applet code")
      Nil
    }
  }
}

fn nearest_click_handler(event) {
  let target = document.target(event)
  case document.closest(target, "[data-click]") {
    Ok(element) -> {
      // Because the closest element is chosen to have data-click this get must return ok
      let assert Ok(handle) = document.dataset_get(element, "click")
      case int.parse(handle) {
        Ok(id) -> Ok(id)
        Error(Nil) -> {
          io.debug(#("not an id", handle))
          Error(Nil)
        }
      }
    }
    Error(Nil) -> Error(Nil)
  }
}

pub fn console_log() {
  #(
    t.String,
    t.unit,
    fn(message, k) {
      let env = env.empty()
      let rev = []
      use message <- cast.require(cast.string(message), rev, env, k)
      console.log(message)
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}
