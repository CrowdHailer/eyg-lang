import gleam/io
import gleam/list
import gleam/javascript
import gleam/javascript/array
import gleam/javascript/promise
import plinth/javascript/promisex
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

fn text(value) {
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

fn value(v) {
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

type State {
  State(greeting: String, loud: Bool)
}

// would pull from state
fn greeting(state: State) {
  state.greeting
}

fn loud(state: State) {
  state.loud
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
      text(greeting),
      if_(loud, p([], [text(greeting)]), text(value(""))),
    ],
  )
}

// maybe return a list of elements from page.
// if needs to memoize the result
// How do components recieve something smaller than the full state

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
      let initial = State("world", False)
      let #(e, update) = page()(initial)
      document.append(x, e)
      use _ <- promise.await(promisex.wait(1000))
      let new = State(..initial, greeting: "Everyone")
      update(new)
      use _ <- promise.await(promisex.wait(2000))
      let new = State(loud: True, greeting: "Final")
      update(new)
      promise.resolve(Nil)
    },
  )

  // todo
  // io.debug(page()("foo"))

  // panic
  todo("end of run")
}
