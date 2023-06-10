// Slow due to a lot of calls to list.map
import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/javascript
import gleam/javascript/array
import gleam/javascript/promise
import plinth/browser/console
import plinth/browser/document
import plinth/javascript/promisex
import eygir/expression as e
import eygir/decode

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
      False -> {
        javascript.set_reference(value, latest)
        do_update(latest)
      }
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

fn attribute(key, signal) {
  fn(element) {
    let current = signal()
    let value = javascript.make_reference(current)
    let do_update = document.set_attribute(element, key, _)
    let update = fn() {
      let latest = signal()
      case latest == javascript.dereference(value) {
        True -> Nil
        False -> {
          javascript.set_reference(value, latest)
          do_update(latest)
        }
      }
    }
    do_update(current)
    update
  }
}

fn class(signal) {
  attribute("class", signal)
}

fn click(signal) {
  attribute("data-click", signal)
}

fn p(children) {
  el("p", [], children)
}

fn match(create) {
  let pin = document.create_element("span")
  let #(elements, try_update) = create()

  let elements_ref = javascript.make_reference(elements)
  let try_update_ref = javascript.make_reference(try_update)
  let update = fn() {
    case javascript.dereference(try_update_ref)() {
      Ok(Nil) -> Nil
      Error(Nil) -> {
        list.map(javascript.dereference(elements_ref), document.remove)
        let #(elements, try_update) = create()
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

fn if_(predicate, true true, false false) {
  match(fn() { if_create(predicate, true, false) })
}

fn if_create(predicate, true, false) {
  case predicate() {
    True -> {
      let #(elements, updates) = list.unzip(true)
      let update = fn() {
        list.map(updates, fn(u) { u() })
        Nil
      }
      let try_update = fn() {
        case predicate() {
          True -> Ok(update())
          False -> Error(Nil)
        }
      }
      #(elements, try_update)
    }
    False -> {
      let #(elements, updates) = list.unzip(false)
      let update = fn() {
        list.map(updates, fn(u) { u() })
        Nil
      }
      let try_update = fn() {
        case predicate() {
          False -> Ok(update())
          True -> Error(Nil)
        }
      }
      #(elements, try_update)
    }
  }
}

fn option(option, some some, none none) {
  match(fn() { option_create(option, some, none) })
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

fn expression(
  exp,
  var var,
  lambda lambda,
  apply apply,
  let_ let_,
  integer integer,
  binary binary,
) {
  match(fn() {
    expression_create(exp, var, lambda, apply, let_, integer, binary)
  })
}

fn fragment(children) {
  let #(elements, updates) = list.unzip(children)
  let update = fn() {
    list.map(updates, fn(u) { u() })
    Nil
  }
  #(elements, update)
}

fn expression_create(exp, var, lambda, apply, let_, integer, binary) {
  case exp() {
    e.Variable(label) -> {
      let #(get, set) = make(label)
      let #(elements, update) = fragment(var(get))
      let try_update = fn() {
        case exp() {
          e.Variable(new) -> {
            set(new)
            Ok(update())
          }
          _ -> Error(Nil)
        }
      }
      #(elements, try_update)
    }
    e.Lambda(label, body) -> {
      let #(get_label, set_label) = make(label)
      let #(get_body, set_body) = make(body)
      let #(elements, update) = fragment(lambda(get_label, get_body))
      let try_update = fn() {
        case exp() {
          e.Lambda(label, body) -> {
            set_label(label)
            set_body(body)

            Ok(update())
          }
          _ -> Error(Nil)
        }
      }
      #(elements, try_update)
    }
    e.Apply(func, body) -> {
      let #(get_func, set_func) = make(func)
      let #(get_body, set_body) = make(body)
      let #(elements, update) = fragment(apply(get_func, get_body))
      let try_update = fn() {
        case exp() {
          e.Apply(func, body) -> {
            set_func(func)
            set_body(body)

            Ok(update())
          }
          _ -> Error(Nil)
        }
      }
      #(elements, try_update)
    }
    e.Let(label, value, then) -> {
      let #(get_label, set_label) = make(label)
      let #(get_value, set_value) = make(value)
      let #(get_then, set_then) = make(then)

      let #(elements, update) = fragment(let_(get_label, get_value, get_then))
      let try_update = fn() {
        case exp() {
          e.Let(label, value, then) -> {
            set_label(label)
            set_value(value)
            set_then(then)

            Ok(update())
          }
          _ -> Error(Nil)
        }
      }
      #(elements, try_update)
    }
    e.Integer(value) -> {
      let #(get, set) = make(value)
      let #(elements, update) = fragment(integer(get))
      let try_update = fn() {
        case exp() {
          e.Integer(new) -> {
            set(new)
            Ok(update())
          }
          _ -> Error(Nil)
        }
      }
      #(elements, try_update)
    }
    e.Binary(value) -> {
      let #(get, set) = make(value)
      let #(elements, update) = fragment(binary(get))
      let try_update = fn() {
        case exp() {
          e.Binary(new) -> {
            set(new)
            Ok(update())
          }
          _ -> Error(Nil)
        }
      }
      #(elements, try_update)
    }
    _ -> {
      // let #(get, set) = make(value)
      let #(elements, update) = fragment([text(static("unknown"))])
      let try_update = fn() {
        case exp() {
          // e.Binary(new) -> {
          //   set(new)
          //   Ok(update())
          // }
          _ -> Error(Nil)
        }
      }
      #(elements, try_update)
    }
  }
}

pub type State {
  State(
    greeting: String,
    active: Bool,
    session: Option(String),
    source: e.Expression,
  )
}

// list of updates, how does svelte batch updates

fn projection(exp) {
  // This is going to be a problem recursivly will blow the stack
  expression(
    exp,
    var: fn(label) { [text(label), text(static("  "))] },
    lambda: fn(label, body) {
      [text(label), text(static(" lambda ")), ..projection(body)]
    },
    apply: fn(func, arg) { list.append(projection(func), projection(arg)) },
    let_: fn(label, value, then) {
      let elements =
        [text(static("let ")), text(label)]
        |> list.append(projection(value))
        |> list.append([text(static("\n"))])
        |> list.append(projection(then))
      io.debug(list.length(elements))
      elements
    },
    integer: fn(value) { [text(fn() { int.to_string(value()) })] },
    binary: fn(value) { [text(static("\"")), text(value), text(static("\""))] },
  )
}

// app is the stateful bit.
pub fn app(json) {
  let assert Ok(source) = decode.decoder(json)
  // component is actually context
  let page = component(fn(exp) { projection(exp) })
  let #(signal, set) = make(source)
  let #(elements, update) = page(signal())
  promise.map(
    promisex.wait(2000),
    fn(_) {
      let assert e.Let(label, std, rest) = source
      let exp = e.Let(label, e.Vacant(""), rest)
      update(exp)
    },
  )
  #(array.from_list(elements), update)
}

pub fn run() {
  let page =
    component(fn(props: Signal(State)) {
      let greeting = fn() { props().greeting }
      // form below needed if signals are results
      // let greeting = map(props, fn(p) { p.greeting })
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
            click(static("foo")),
          ],
          [
            text(greeting),
            ..if_(
              fn() { option.is_some(props().session) },
              true: [text(static("world"))],
              false: [text(static("world!!"))],
            )
          ],
        ),
        p(projection(fn() { props().source })),
        ..option(
          session,
          some: fn(session_id) { [text(session_id), text(greeting)] },
          none: [text(static("nonee"))],
        )
      ]
    })

  let #(state, set_state) =
    make(State(
      greeting: "hello",
      active: False,
      session: None,
      source: e.Lambda("x", e.Variable("x")),
    ))
  let #(elements, update) = page(state())
  let update_state = fn(f) {
    let new = f(state())
    set_state(new)
    update(new)
  }

  let assert [target, ..] =
    array.to_list(document.query_selector_all("[data-easel=\"large\"]"))

  document.on_click(fn(event) {
    console.log(event)
    update_state(fn(s) { State(..s, active: !s.active) })
  })
  list.map(elements, document.append(target, _))

  use _ <- promise.await(promisex.wait(1000))
  update_state(fn(s) {
    State(
      ..s,
      session: Some("foo"),
      source: e.Lambda("x", e.Lambda("y", e.Variable("y"))),
    )
  })
  use _ <- promise.await(promisex.wait(1000))
  update_state(fn(s) { State(..s, session: Some("bar")) })
  use _ <- promise.await(promisex.wait(1000))
  update_state(fn(s) {
    State(
      ..s,
      greeting: "done",
      source: e.Lambda("x", e.Lambda("y", e.Variable("z"))),
    )
  })

  // console.log(array.from_list(elements))
  promise.resolve(Nil)
}
