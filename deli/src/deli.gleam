import gleam/io
import gleam/list

pub type Ctrl(a, r) {
  Pure(r)
  Yield(marker: String, f: fn(a) -> r, k: fn(r) -> Ctrl(a, r))
}

fn add(a, b) {
  Pure(a + b)
}

// read the paper I just discovered -> write down join point
// Evv is recursive has own under value in list

// e has to be a fn taking evidence and returning ctrl
fn handle(marker, h, e, w) {
  case e {
    Pure(x) -> Pure(x)
    Yield(m, f, k) if m != marker -> Yield(m, f, todo)
    Yield(m, f, k) -> 
  }
}

fn perform(marker, value, evidence) {
  let assert Ok(#(_, f)) = list.at(evidence, 0)
  // f needs to be under reduced evidence
  Yield(marker, fn(k) { f(value, k) }, fn(x) { Pure(x) })
}

pub fn main() {
  run()
  |> io.debug
  io.println("Hello from deli!")
}

// I think e is monad
fn bind(e, g) -> fn(Int) -> Ctrl(Int, Int) {
  fn(w) -> Ctrl(Int, Int) {
    case e {
      Pure(x) -> g(x, w)
      Yield(m, f, k) -> todo
    }
  }
  // Yield(m, f, fn(x) -> Ctrl(Int, Int) { g(k(x), w) })
}

fn run() {
  // use a <- bind(Pure(5))
  handle(
    "log",
    fn(msg, k) {
      io.debug(msg)
      k(Nil)
    },
    fn(w) {
      1 + 2
      perform("log", "hi", w)
    },
    [],
  )
}
