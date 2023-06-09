import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/javascript
import gleam/javascript/array
import gleam/javascript/promise
import plinth/browser/console
import plinth/browser/document
import plinth/javascript/promisex

pub type Signal(a) =
  fn() -> a

fn make(value) {
  let ref = javascript.make_reference(value)
  #(fn() { javascript.dereference(ref) }, javascript.set_reference(ref, _))
}

// don't bother with map, just dot access is ok

fn static(x) {
  fn() { x }
}

fn component(create) {
  fn(value) {
    let #(get, set) = make(value)
    let #(elements, updates) = list.unzip(create(get))
    let update = fn() {
      list.map(updates, fn(u) { u() })
      Nil
    }
    #(
      elements,
      fn(value) {
        set(value)
        // set in request animation frame
        update()
      },
    )
  }
}

fn text(signal) {
  let text = document.create_element("span")
  let current = signal()
  let value = javascript.make_reference(current)
  let do_update = document.set_text(text, _)
  let update = fn() {
    let latest = signal()
    case latest == javascript.dereference(value) {
      True -> Nil
      False -> do_update(latest)
    }
  }
  do_update(current)
  #(text, update)
}

fn el(tag, attributes, children) {
  let element = document.create_element(tag)
  let attr_updates = list.map(attributes, fn(a) { a(element) })
  let #(children, children_updates) = list.unzip(children)
  list.map(children, document.append(element, _))

  let update = fn() {
    list.map(attr_updates, fn(u) { u() })
    list.map(children_updates, fn(u) { u() })
    Nil
  }
  // always return try_update
  // but weird silent failure if out of place
  // fn(){list.try_all(updates, exec)}
  #(element, update)
}

fn class(signal) {
  fn(element) {
    let current = signal()
    let value = javascript.make_reference(current)
    let do_update = document.set_attribute(element, "class", _)
    let update = fn() {
      let latest = signal()
      case latest == javascript.dereference(value) {
        True -> Nil
        False -> do_update(latest)
      }
    }
    do_update(current)
    update
  }
}

fn p(children) {
  el("p", [], children)
}

fn if_(predicate, true, false) {
  todo
}

fn option_create(option, some, none) {
  case option() {
    Some(value) -> {
      let #(get, set) = make(value)
      let #(elements, updates) = list.unzip(some(get))
      let update = fn() {
        list.map(updates, fn(u) { u() })
        Nil
      }
      let try_update = fn() {
        case option() {
          Some(new) -> {
            set(new)
            Ok(update())
          }
          None -> Error(Nil)
        }
      }
      #(elements, try_update)
    }
    None -> {
      let #(elements, updates) = list.unzip(none)
      let update = fn() {
        list.map(updates, fn(u) { u() })
        Nil
      }
      let try_update = fn() {
        case option() {
          None -> {
            Ok(update())
          }
          Some(_) -> Error(Nil)
        }
      }
      #(elements, try_update)
    }
  }
}

fn option(option, some some, none none) {
  let pin = document.create_element("span")
  let #(elements, try_update) = option_create(option, some, none)

  let elements_ref = javascript.make_reference(elements)
  let try_update_ref = javascript.make_reference(try_update)
  let update = fn() {
    case javascript.dereference(try_update_ref)() {
      Ok(Nil) -> Nil
      Error(Nil) -> {
        list.map(javascript.dereference(elements_ref), document.remove)
        let #(elements, try_update) = option_create(option, some, none)
        list.fold(
          elements,
          pin,
          fn(acc, new) {
            document.insert_element_after(acc, new)
            new
          },
        )
        javascript.set_reference(elements_ref, elements)
        javascript.set_reference(try_update_ref, try_update)
        Nil
      }
    }
  }
  // weird but after try_update we only have one update
  [#(pin, update), ..list.map(elements, fn(e) { #(e, fn() { Nil }) })]
}

pub type State {
  State(greeting: String, active: Bool, session: Option(String))
}

// list of updates, how does svelte batch updates

pub fn run() {
  let page =
    component(fn(props: Signal(State)) {
      let greeting = fn() { props().greeting }
      let session = fn() { props().session }

      [
        el(
          "p",
          [
            class(fn() {
              case props().active {
                True -> "font-bold"
                False -> ""
              }
            }),
          ],
          [text(greeting), text(static("world"))],
        ),
        ..option(
          session,
          some: fn(session_id) { [text(session_id), text(greeting)] },
          none: [text(static("nonee"))],
        )
      ]
    })
  let assert [target, ..] =
    array.to_list(document.query_selector_all("[data-easel=\"large\"]"))

  let #(elements, update) =
    page(State(greeting: "hello", active: False, session: None))
  list.map(elements, document.append(target, _))
  // console.log(array.from_list(elements))
  use _ <- promise.await(promisex.wait(1000))
  update(State(greeting: "hello!", active: True, session: Some("foooo")))
  use _ <- promise.await(promisex.wait(1000))
  update(State(greeting: "hello!", active: True, session: Some("bar")))
  use _ <- promise.await(promisex.wait(1000))
  update(State(greeting: "done", active: True, session: Some("bar")))

  // console.log(array.from_list(elements))
  promise.resolve(Nil)
}
