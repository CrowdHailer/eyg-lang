pub type Ctl {
  Pure(Int)
  Yield(marker: String, op: fn(fn(Int) -> Ctl) -> Ctl, cont: fn(Int) -> Ctl)
}

pub fn kcompose(g, f) {
  fn(x) {
    f(x)
    |> bind(g)
  }
}

fn bind(ctl, f) -> Ctl {
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

pub fn run() {
  prompt(
    "read",
    fn() {
      use a <- bind(Pure(5))
      use b <- bind(yield("read", fn(k) { k(2) }))
      Pure(a + b)
    },
  )
}
