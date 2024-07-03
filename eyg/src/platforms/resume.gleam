import eyg/runtime/cast
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import eygir/annotated as e
import eygir/decode
import gleam/dict
import gleam/dynamic
import gleam/javascript
import gleam/javascript/array
import gleam/javascript/map
import gleam/list
import gleam/result
import gleam/string
import harness/stdlib
import plinth/browser/document
import plinth/browser/element
import plinth/browser/event
import plinth/javascript/console

fn handle_click(event, states) {
  use target <- result.then(element.closest(
    dynamic.unsafe_coerce(event.target(event)),
    "*[on\\:click]",
  ))
  use container <- result.then(element.closest(target, "[r\\:container]"))
  use key <- result.then(element.get_attribute(target, "on:click"))
  use #(action, env) <- result.then(map.get(states, container))
  // TODO get attribute and multiple sources
  let answer = r.resume(action, [#(v.Str(key), Nil)], env, dict.new())
  // console.log(answer)
  let assert Ok(term) = answer
  // console.log(v.debug(term))
  case term {
    v.Tagged("Ok", return) -> {
      // console.log(v.debug(return))
      let assert Ok(content) = cast.field("content", cast.as_string, return)
      let assert Ok(action) = cast.field("action", cast.any, return)
      element.set_inner_html(container, content)
      // Need native map because js objects are deep equal true
      Ok(map.set(states, container, #(action, env)))
    }
    _ -> {
      console.log("bad stuff")
      Ok(states)
    }
  }
}

pub fn run() {
  let scripts =
    document.query_selector_all("script[type=\"application/eygir.json\"]")
    |> array.to_list()
  let states =
    list.filter_map(scripts, fn(script) {
      use container <- result.then(element.closest(script, "[r\\:container]"))
      use source <- result.then(
        decode.from_json(string.replace(element.inner_text(script), "\\/", "/"))
        |> result.map_error(fn(_) { Nil }),
      )
      let env = stdlib.env()
      let source = e.add_annotation(source, Nil)
      let assert Ok(action) = r.execute(source, env, dict.new())
      // TODO remove env, it doesn't matter call to call
      Ok(#(container, #(action, env)))
    })
    |> list.fold(map.new(), fn(map, item) {
      let #(key, value) = item
      map.set(map, key, value)
    })
  states
  |> console.log

  let ref = javascript.make_reference(states)
  document.add_event_listener("click", fn(event) {
    let states = javascript.dereference(ref)
    let assert Ok(states) = handle_click(event, states)
    javascript.set_reference(ref, states)
    Nil
  })
  // case  {
  //   Ok(script) -> {
  //     // console.log(script)
  //     let assert Ok(source) =
  //       decode.from_json(string.replace(element.inner_text(script), "\\/", "/"))
  //     // console.log(source)
  //     // env needs builtins
  //     let env = stdlib.env()
  //     let rev = []
  //     let assert #(action, env) = r.resumable(source, env, None)
  //     let ref = javascript.make_reference(action)

  //     document.add_event_listener(
  //       "click",
  //       fn(event) {
  //         case element.closest(event.target(event), "*[on\\:click]") {
  //           Ok(target) ->
  //             case element.closest(target, "[r\\:container]") {
  //               Ok(container) -> {
  //                 let k = Some(state.Stack(r.CallWith(v.Str("0"), [], env), None))
  //                 let c = javascript.dereference(ref)
  //                 let #(answer, _) = r.loop_till(state.V(c), rev, env, k)
  //                 // console.log(answer)
  //                 let assert Ok(term) = answer
  //                 // console.log(v.debug(term))
  //                 case term {
  //                   v.Tagged("Ok", return) -> {
  //                     // console.log(v.debug(return))
  //                     let assert Ok(v.Str(content)) =
  //                       r.field(return, "content")
  //                     let assert Ok(action) = r.field(return, "action")
  //                     javascript.set_reference(ref, Ok(action))
  //                     element.set_inner_html(container, content)
  //                   }
  //                   _ -> {
  //                     console.log("bad stuff")
  //                     Nil
  //                   }
  //                 }
  //                 Nil
  //               }

  //               Error(Nil) -> Nil
  //             }
  //           Error(Nil) -> Nil
  //         }
  //       },
  //     )
  //   }
  //   Error(Nil) -> Nil
  // }
  // document.add_event_listener(
  //   "click",
  //   fn(event) {
  //     case element.closest(event.target(event), "*[on\\:click]") {
  //       Ok(target) ->
  //         case element.closest(target, "[r\\:container]") {
  //           Ok(container) -> {
  //             // console.log(#("clicked", target))

  //             case
  //               document.query_selector(
  //                 "script[type=\"application/eygir.json\"]",
  //               )
  //             {
  //               Ok(script) -> {
  //                 // console.log(script)
  //                 let assert Ok(source) =
  //                   decode.from_json(string.replace(
  //                     element.inner_text(script),
  //                     "\\/",
  //                     "/",
  //                   ))
  //                 // console.log(source)
  //                 // env needs builtins
  //                 let env = stdlib.env()
  //                 let rev = []
  //                 let k = Some(state.Stack(r.CallWith(v.Str("0"), [], env), None))
  //                 let answer = r.execute(source, env, k)
  //                 // console.log(answer)
  //                 let assert Ok(term) = answer
  //                 // console.log(v.debug(term))
  //                 case term {
  //                   v.Tagged("Ok", v.Str(content)) ->
  //                     element.set_inner_html(container, content)
  //                   _ -> {
  //                     console.log("bad stuff")
  //                     Nil
  //                   }
  //                 }
  //                 Nil
  //               }
  //               Error(_) -> Nil
  //             }
  //           }

  //           Error(Nil) -> Nil
  //         }
  //       Error(Nil) -> Nil
  //     }
  //   },
  // )
}
