import easel/embed
import eyg/analysis/jm/type_ as t
import eyg/runtime/cast
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eygir/annotated as e
import eygir/decode
import gleam/dict
import gleam/dynamic
import gleam/dynamicx
import gleam/int
import gleam/io
import gleam/javascript
import gleam/javascript/array
import gleam/list
import gleam/listx
import gleam/result
import gleam/string
import harness/stdlib
import plinth/browser/document
import plinth/browser/element
import plinth/browser/event
import plinth/javascript/console

pub fn run() {
  let containers = document.query_selector_all("[data-ready]")
  // This is a the location for a style of qwikloader, add global handlers and then look up attributes.
  // i.e. data-click.
  // How do i handle adding state to something being active i.e. in memory value of state
  array.map(containers, start)
}

fn start(container) {
  let assert Ok(program) = element.dataset_get(container, "ready")
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
  case document.query_selector("script[type=\"application/eygir\"]") {
    Ok(script) -> {
      console.log(script)
      let assert Ok(source) =
        decode.from_json(string.replace(element.inner_text(script), "\\/", "/"))
      {
        let env = stdlib.env()
        let rev = []
        let k = dict.new()
        let source = e.add_annotation(source, Nil)
        let assert Ok(term) = r.execute(source, env, k)
        use func <- result.then(cast.field("func", cast.any, term))
        use arg <- result.then(cast.field("arg", cast.any, term))
        // run func arg can be a thing
        // weird return wrapping for cast
        // stdlib only builtins used
        let actions = javascript.make_reference([])
        let handlers =
          dict.new()
          |> dict.insert("Update", fn(action) {
            let saved = javascript.dereference(actions)
            let id = int.to_string(list.length(saved))
            let saved = [action, ..saved]
            javascript.set_reference(actions, saved)
            Ok(v.Str(id))
          })
          |> dict.insert("Log", console_log().2)
        let state = javascript.make_reference(arg)
        let render = fn() {
          let current = javascript.dereference(state)
          let result = r.resume(func, [#(current, Nil)], env, handlers)
          let _ = case result {
            Ok(v.Str(page)) -> element.set_inner_html(root, page)
            _ -> {
              io.debug(#("unexpected", result))
              panic("nope")
            }
          }
        }

        document.add_event_listener("click", fn(event) {
          case nearest_click_handler(event) {
            Ok(id) -> {
              case listx.at(list.reverse(javascript.dereference(actions)), id) {
                Ok(code) -> {
                  // handle effects
                  let current = javascript.dereference(state)
                  // io.debug(javascript.dereference(actions))
                  let assert Ok(next) =
                    r.resume(code, [#(current, Nil)], env, dict.new())
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
        })
        render()
        Ok(#(state.V(func), rev, env, k))
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
  let target = event.target(event)
  let target = dynamicx.unsafe_coerce(target)
  case element.closest(target, "[data-click]") {
    Ok(element) -> {
      // Because the closest element is chosen to have data-click this get must return ok
      let assert Ok(handle) = element.dataset_get(element, "click")
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
  #(t.String, t.unit, fn(message) {
    use message <- result.then(cast.as_string(message))
    console.log(message)
    Ok(v.unit)
  })
}
