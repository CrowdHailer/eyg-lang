import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import javascript/mutable_reference as ref
import plinth/browser/document
import plinth/browser/element

// I think these are observable not signals because subscription rather than get in a call

pub type Observable(a) =
  #(a, fn(fn(a) -> Nil) -> Nil)

pub fn make(initial: a) -> #(Observable(a), fn(a) -> Nil) {
  let value = ref.new(initial)
  let observers = ref.new([])

  let observable = #(initial, fn(sub) {
    ref.update(observers, list.prepend(_, sub))
    Nil
  })
  // bit weird that we don't update the value in tuple but we can't
  // observable only used to build subscriptions
  let set = fn(new) {
    case new == ref.get(value) {
      True -> Nil
      False -> {
        ref.set(value, new)
        list.map(ref.get(observers), fn(observer) { observer(new) })
        Nil
      }
    }
  }

  #(observable, set)
}

pub fn map(observable: Observable(a), m: fn(a) -> b) -> Observable(b) {
  let #(outer, observe) = observable
  let initial = m(outer)
  let value = ref.new(initial)
  let observe = fn(observer) {
    observe(fn(outer) {
      let new = m(outer)
      case new == ref.get(value) {
        True -> Nil
        False -> observer(new)
      }
    })
  }
  #(initial, observe)
}

pub fn static(value) {
  // never update
  #(value, fn(_) { Nil })
}

pub fn component(create) {
  fn(initial) {
    let #(observable, set) = make(initial)
    let node = create(observable)
    #(node, set)
  }
}

fn el(tag, children) {
  let element = document.create_element(tag)
  list.map(children, element.append_child(element, _))
  element
}

fn p(children) {
  el("p", children)
}

pub fn text(o: Observable(String)) {
  let text = document.create_element("span")
  element.set_inner_text(text, o.0)
  o.1(element.set_inner_text(text, _))
  text
}

pub fn option(
  observable: Observable(Option(a)),
  some some: fn(Observable(a)) -> List(element.Element),
  none none: List(element.Element),
) {
  // svelte uses empty text node for pin, so it doesn't effect element order for styling
  let pin = document.create_element("span")
  let create = fn(option: Option(a)) {
    case option {
      Some(value) -> {
        #(
          some(
            #(value, fn(sub) {
              // keep observers in this component scope
              observable.1(fn(outer) {
                case outer {
                  Some(new) -> sub(new)
                  None -> Nil
                }
              })
            }),
          ),
          fn(new) {
            case new {
              Some(_) -> Ok(Nil)
              None -> Error(Nil)
            }
          },
        )
      }

      None -> #(none, fn(new) {
        case new {
          None -> Ok(Nil)
          Some(_) -> Error(Nil)
        }
      })
    }
  }
  let #(elements, try_update) = create(observable.0)
  let elements_ref = ref.new(elements)
  let try_update_ref = ref.new(try_update)

  observable.1(fn(new) {
    io.debug(#("nnnp", new))
    case ref.get(try_update_ref)(new) {
      Ok(Nil) -> Nil
      Error(Nil) -> {
        list.map(ref.get(elements_ref), element.remove)
        let #(elements, try_update) = create(new)
        list.fold(elements, pin, fn(acc, new) {
          element.insert_adjacent_element(acc, element.AfterEnd, new)
          new
        })
        ref.set(elements_ref, elements)
        ref.set(try_update_ref, try_update)
        Nil
      }
    }
  })

  [pin, ..elements]
}

pub type State {
  State(greeting: String, active: Bool, session: Option(String))
}

pub fn run() {
  let assert [target, ..] =
    array.to_list(document.query_selector_all("[data-easel=\"large\"]"))
  let page =
    component(fn(props) {
      let greeting = map(props, fn(props: State) { props.greeting })
      let session = map(props, fn(props: State) { props.session })

      [
        p([text(greeting), text(static(" world!"))]),
        ..option(
          session,
          some: fn(session_id) { [text(session_id), text(greeting)] },
          none: [text(static("nonee"))],
        )
      ]
    })
  let #(elements, update) =
    page(State(greeting: "hello", active: False, session: None))
  list.map(elements, element.append_child(target, _))
  // console.log(array.from_list(elements))
  use _ <- promise.await(promise.wait(1000))
  update(State(greeting: "hello!", active: True, session: Some("foooo")))
  use _ <- promise.await(promise.wait(1000))
  update(State(greeting: "hello!", active: True, session: Some("bar")))
  use _ <- promise.await(promise.wait(1000))
  update(State(greeting: "done", active: True, session: Some("bar")))

  // console.log(array.from_list(elements))
  promise.resolve(Nil)
}
