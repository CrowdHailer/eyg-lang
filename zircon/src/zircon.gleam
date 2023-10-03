import gleam/io
import gleam/int
import gleam/list
import gleam/string
import gleam/javascript

pub fn main() {
  // There needs to be a root, root runs once
  // use c <- count()
  io.println("Hello from zircon!")
  let #(count, set_count) = create_signal(3)

  io.println(string.append("initial read: ", int.to_string(count([]))))
  create_effect(fn(context) {
    io.debug(count(context))
    Nil
  })
  set_count(5)
  // io.println(string.append("updated read: ", int.to_string(count())))
  set_count(count([]) * 2)
  // io.println(string.append("updated read: ", int.to_string(count())))
}

pub type Runner {
  Runner(execute: fn() -> Nil)
}

// context is a stack
pub fn create_signal(value) {
  let ref = javascript.make_reference(value)
  let subscriptions = javascript.make_reference([])

  let read = fn(context) {
    case context {
      [] -> Nil
      [running, ..] -> {
        javascript.update_reference(subscriptions, fn(s) { [running, ..s] })
        Nil
      }
    }
    javascript.dereference(ref)
  }
  let write = fn(value) {
    javascript.set_reference(ref, value)
    list.map(
      javascript.dereference(subscriptions),
      fn(subscription: Effect) { subscription.call([]) },
    )
  }
  #(read, write)
}

pub type Effect {
  Effect(call: fn(List(Effect)) -> Nil)
}

pub fn create_effect(f: fn(List(Effect)) -> Nil) {
  f([Effect(f)])
}
