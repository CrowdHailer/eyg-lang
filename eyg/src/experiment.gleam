// svelte uses empty text nodes as anchor
import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/javascript
import gleam/javascript/array
import gleam/javascript/promise
import plinth/javascript/promisex
import plinth/browser/console
import plinth/browser/document

fn p(attributes, nodes) {
  fn(value: s) {
    let element = document.create_element("p")
    let updates: List(fn(s) -> Nil) =
      list.map(
        nodes,
        fn(create) {
          let #(child, update) = create(value)
          document.append(element, child)
          update
        },
      )
      |> list.append(list.map(
        attributes,
        fn(cast) -> fn(s) -> Nil {
          let #(name, value) = cast(value)
          document.set_attribute(element, name, value)
          fn(value) {
            let #(name, value) = cast(value)
            document.set_attribute(element, name, value)
          }
        },
      ))

    #(
      element,
      fn(new) {
        list.map(updates, fn(u) { u(new) })
        Nil
      },
    )
  }
}

type Component(a) =
  fn(a) -> #(document.Element, fn(a) -> Nil)

fn text(value: fn(a) -> String) -> Component(a) {
  fn(state) {
    let element = document.create_element("span")
    let initial = value(state)
    let cache = javascript.make_reference(initial)
    document.set_text(element, initial)
    #(
      element,
      fn(state) {
        let new = value(state)
        javascript.update_reference(
          cache,
          fn(old) {
            case old == new {
              True -> Nil
              False -> document.set_text(element, new)
            }
            new
          },
        )
        Nil
      },
    )
  }
}

fn attr(name, value) {
  fn(state) { #(name(state), value(state)) }
}

fn class(f) {
  fn(state) { #("class", f(state)) }
}

fn value(v: a) {
  fn(_) { v }
}

fn nvalue(v) {
  fn(_) { v }
}

fn if_(predicate, yes, no) {
  fn(state) {
    case predicate(state) {
      True -> yes(state)
      False -> no(state)
    }
  }
}

// TODO use case as a wrapper for the lens part, same as text,
// and for place to run cache from option
fn case_(component) -> Component(a) {
  fn(props) {
    let create = component(props)
    let #(element, update) = create(props)
    #(element, fn(_) { todo })
  }
}

// add shrink here
fn option(some: Component(a), none: Component(Nil)) -> Component(Option(a)) {
  fn(state: Option(a)) {
    // TODO should be empty text node
    let pin = document.create_element("span")
    let create = fn(state) {
      case state {
        Some(value) -> {
          let #(element, update) = some(value)
          #(
            element,
            fn(new) {
              case new {
                // Internal node checks equality to previous value
                Some(new) -> Ok(update(new))
                _ -> Error(Nil)
              }
            },
          )
        }
        // #(element, Some(update))
        // #(
        None -> {
          let #(element, update) = none(Nil)
          // return key and updates with assert
          #(
            element,
            fn(new) {
              case new {
                None -> Ok(update(Nil))
                _ -> Error(Nil)
              }
            },
          )
        }
      }
    }
    let cache = javascript.make_reference(create(state))
    // TODO return list of elements
    #(
      pin,
      fn(state) {
        let #(element, try_update) = javascript.dereference(cache)
        case try_update(state) {
          Ok(Nil) -> Nil
          Error(Nil) -> {
            // delete element
            document.remove(element)
            let #(e, t) = create(state)
            document.insert_element_after(pin, e)
            javascript.set_reference(cache, #(e, t))
            Nil
          }
        }
      },
    )
  }
}

pub fn lens(zoom, element) {
  fn(s) {
    let #(e, u) = element(zoom(s))
    #(e, fn(s) { u(zoom(s)) })
  }
}

type State {
  State(greeting: String, loud: Bool, session: Option(String))
}

// would pull from state
fn greeting(state: State) {
  state.greeting
}

fn loud(state: State) {
  state.loud
}

fn session(state: State) {
  state.session
}

//
// string if etc can wrap the text apstraction

fn page() {
  p(
    [
      class(if_(loud, value("bold underline text-red-500"), value(""))),
      attr(value("foo"), greeting),
    ],
    [
      text(value("hello ")),
      lens(session, option(text(fn(x) { x }), text(value("bob")))),
      // unroll lens/
      // swtich can't return list would force matching lengths of lists. lot's of anon functions probably slow
      // and this is meant to be fast (enough)
      // match! is special for current value, but definetly no way to type
      // case_(session, option(text(match(id)), text(context(greeting))))
      // case_(session, option(Foo(match(id), context(greeing)), Foo(context(greeting))))
      // can't type x is not a value i.e in None there is no x
      // case_(session, option(fn(x, state) {
      //   Foo
      //   Bar
      // }))
      text(greeting),
      // switch([
      //   #(is_some),

      // ]),
      if_(loud, p([], [text(greeting)]), text(value(""))),
    ],
  )
}

// maybe return a list of elements from page.
// if needs to memoize the result
// How do components recieve something smaller than the full state
// get innerHTML for writing tests?

// TODO make note appending an element that is already in the dom removes it from the old position
pub fn run() {
  io.debug("hello")
  let containers =
    document.query_selector_all("[data-easel=\"large\"]")
    |> io.debug
  let p =
    document.create_element("p")
    |> io.debug
  document.set_text(p, "hello")
  array.map(
    containers,
    fn(x) {
      document.append(x, p)
      let initial = State("world", False, Some("foo"))
      let #(e, update) = page()(initial)
      document.append(x, e)
      use _ <- promise.await(promisex.wait(1000))
      let new = State(..initial, greeting: "Everyone", session: None)
      update(new)
      use _ <- promise.await(promisex.wait(2000))
      let new = State(loud: True, greeting: "Final", session: Some("latest"))
      update(new)
      promise.resolve(Nil)
    },
  )
  // todo
  // io.debug(page()("foo"))

  // panic
  // todo("end of run")
}
