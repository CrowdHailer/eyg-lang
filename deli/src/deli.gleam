import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/list

// pub type Foo(x) {
//   Thing(x)
//   Base(Foo(Nil))
// }

pub type Ctrl {
  Pure(Int)
  Yield(marker: String, op: fn(fn(Int) -> Ctrl) -> Ctrl, cont: fn(Int) -> Ctrl)
}

fn kcompose(g, f) {
  fn(x) {
    f(x)
    |> bind(g)
  }
}

fn bind(ctl, f) -> Ctrl {
  case ctl {
    Pure(x) -> f(x)
    Yield(m, op, cont) -> Yield(m, op, kcompose(f, cont))
  }
}

pub fn yield(marker, op) {
  Yield(marker, op, Pure)
}

pub fn prompt(marker, action) {
  mprompt(marker, action())
}

pub fn mprompt(marker, ctl) {
  case ctl {
    Pure(x) -> Pure(x)
    Yield(m, op, cont) -> {
      let cont = fn(x) { mprompt(marker, cont(x)) }
      case marker == m {
        True -> op(cont)
        False -> Yield(m, op, cont)
      }
    }
  }
}

pub fn main() {
  run()
  |> io.debug
  io.println("Hello from deli!")
}

fn run() {
  prompt(
    "read",
    fn() {
      use a <- bind(Pure(5))
      use b <- bind(yield("read", fn(k) { k(2) }))
      Pure(a + b)
    },
  )
}

// read the paper I just discovered -> write down join point
// Evv is recursive has own under value in list
// Code transformation is too not use a yield if that handler is tail recursive

// e has to be a fn taking evidence and returning ctrl
fn handle(marker, h, e, w) {
  case e {
    Pure(x) -> Pure(x)
    Yield(m, f, k) if m != marker -> Yield(m, f, todo)
    Yield(m, f, k) -> todo
  }
}

fn perform(marker, value, evidence) {
  let assert Ok(#(_, f)) = list.at(evidence, 0)
  // f needs to be under reduced evidence
  Yield(marker, fn(k) { f(value, k) }, fn(x) { Pure(x) })
}

// cont: fn(r) -> Ctrl(a, r),

fn add(a, b) {
  Pure(a + b)
}
