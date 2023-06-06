import gleam/io
import gleam/list
import gleam/javascript/array
import gleam/javascript/promise
import plinth/javascript/promisex
import plinth/browser/document

fn p(attributes, nodes) {
  fn(value) {
    let element = document.create_element("p")
    let updates =
      list.map(
        nodes,
        fn(fragment) {
          let #(child, update) = fragment(value)
          document.append(element, child)
          update
        },
      )
    #(element, fn(new) { list.map(updates, fn(u) { u(new) }) })
  }
}

fn text(value) {
  fn(state) {
    let span = document.create_element("span")
    document.set_text(span, value(state))
    #(
      span,
      fn(next) {
        // TODO only if needed
        document.set_text(span, value(next))
      },
    )
  }
}

fn value(v) {
  fn(_) { v }
}

// would pull from state
fn greeting(state) {
  state
}

// string if etc can wrap the text apstraction

fn page() {
  p([], [text(value("hello")), text(greeting)])
}

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
      let #(e, update) = page()("world!")
      document.append(x, e)
      use _ <- promise.await(promisex.wait(2000))
      update("ballon")
      promise.resolve(Nil)
    },
  )

  // todo
  io.debug(page()("foo"))

  // panic
  todo("end of run")
}
