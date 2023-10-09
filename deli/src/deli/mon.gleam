import gleam/io
import gleam/list

pub type Evv {
  // two arg function for value, k where everything is k's
  Evv(List(#(String, fn(Int, fn(Int) -> Mon) -> Mon)))
}

pub type Ctl {
  Pure(Int)
  Yield(marker: String, op: fn(fn(Int) -> Mon) -> Mon, cont: fn(Int) -> Mon)
}

pub type Mon =
  fn(Evv) -> Ctl

pub fn bind(mon: Mon, f: fn(Int) -> Mon) -> Mon {
  fn(w) {
    case mon(w) {
      Pure(x) -> f(x)(w)
      Yield(m, op, cont) -> Yield(m, op, fn(x) { bind(f(x), cont) })
    }
  }
}

fn take(w, marker) {
  let Evv(evidences) = w
  list.key_find(evidences, marker)
}

pub fn pure(value) {
  fn(_w) { Pure(value) }
}

pub fn perform(marker, value) {
  fn(w) {
    let assert Ok(evidence) = take(w, marker)
    let op = fn(k) { evidence(value, k) }
    Yield(marker, op, pure)
  }
}

// phantom types over marker
fn handle(marker, handler, mon) {
  fn(w) {
    let Evv(w) = w
    case mon(Evv([#(marker, handler), ..w])) {
      Pure(x) -> Pure(x)
      Yield(m, op, cont) if marker == m -> {
        let cont2 = fn(x) { handle(marker, handler, cont(x)) }
        op(cont2)(Evv(w))
      }
      Yield(m, op, cont) -> {
        let cont2 = fn(x) { handle(marker, handler, cont(x)) }
        Yield(m, op, cont2)
      }
    }
  }
}

pub fn run(exec) {
  handle(
    "log",
    fn(lift, k) {
      io.debug(lift)
      k(0)
    },
    {
      handle(
        "read",
        fn(lift, k) {
          let assert Ok(v) = list.at([2, 4, 6], lift)
          k(v)
        },
        exec,
      )
    },
  )(Evv([]))
}
