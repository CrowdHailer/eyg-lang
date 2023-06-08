import gleam/io
import gleam/javascript
import gleam/list

fn signal(value) {
  let ref = javascript.make_reference(value)
  #(fn() { javascript.dereference(ref) }, javascript.set_reference(ref, _))
}

fn component(create) {
  fn(value) {
    let #(get, set) = signal(value)
    let #(elements, updates) = list.unzip(create(get))
    #(
      elements,
      fn(value) {
        set(value)
        list.map(updates, fn(update) { update() })
      },
    )
  }
}

fn text(signal) {
  let value = signal()
  let element = 1
  #(
    element,
    fn() {
      // cache or memory in element
      let new = signal()
      io.debug(new)
    },
  )
  // update
}

fn p(children) {
  let element = 2
  let #(children, updates) = list.unzip(children)
  let update = fn() { list.map(updates, fn(u) { u() }) }
  io.debug(#("childe", children))
  #(element, update)
}

fn const_(x) {
  fn() { x }
}

pub type State {
  State(greeting: String)
}

pub type Signal(a) =
  fn() -> a

// list of updates, how does svelte batch updates

pub fn run() {
  let page =
    component(fn(props: Signal(State)) {
      let greeting = fn() { props().greeting }
      //   let g = map(props, _.greeting)
      [p([text(greeting), text(const_("world"))])]
    })

  let #(e, update) = page(State(greeting: "hello"))
  update(State(greeting: "foo"))
  update(State(greeting: "bar"))
}
