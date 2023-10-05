import gleam/map
import gleam/option.{None, Some}
import gleam/string
import plinth/browser/document
import plinth/browser/element
import plinth/browser/event
import plinth/javascript/console
import eygir/decode
import eyg/runtime/interpreter as r
import harness/stdlib

pub fn run() {
  // console.log(document.document())
  document.add_event_listener(
    "click",
    fn(event) {
      case element.closest(event.target(event), "*[on\\:click]") {
        Ok(target) ->
          case element.closest(target, "[r\\:container]") {
            Ok(container) -> {
              // console.log(#("clicked", target))

              case
                document.query_selector(
                  "script[type=\"application/eygir.json\"]",
                )
              {
                Ok(script) -> {
                  // console.log(script)
                  let assert Ok(source) =
                    decode.from_json(string.replace(
                      element.inner_text(script),
                      "\\/",
                      "/",
                    ))
                  // console.log(source)
                  // env needs builtins
                  let env = stdlib.env()
                  let rev = []
                  let k = Some(r.Kont(r.CallWith(r.Binary("0"), [], env), None))
                  let answer = r.eval(source, env, k)
                  // console.log(answer)
                  let assert r.Value(term) = answer
                  // console.log(r.to_string(term))
                  case term {
                    r.Tagged("Ok", r.Binary(content)) ->
                      element.set_inner_html(container, content)
                    _ -> {
                      console.log("bad stuff")
                      Nil
                    }
                  }
                  Nil
                }
                Error(_) -> Nil
              }
            }

            Error(Nil) -> Nil
          }
        Error(Nil) -> Nil
      }
    },
  )
}
