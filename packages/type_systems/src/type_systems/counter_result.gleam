pub type CounterResult(value, reason) =
  fn(Int) -> Result(#(Int, value), reason)

pub fn fresh(k) -> CounterResult(_, _) {
  fn(current) {
    case k(current)(current + 1) {
      Ok(#(next, value)) -> Ok(#(next, value))
      Error(reason) -> Error(reason)
    }
  }
}

pub fn ok(value) -> CounterResult(_, _) {
  fn(current) { Ok(#(current, value)) }
}

pub fn stop(reason) -> CounterResult(_, _) {
  fn(_current) { Error(reason) }
}

pub fn bind(m, then) -> CounterResult(_, _) {
  fn(current) {
    case m(current) {
      Ok(#(next, value)) -> then(value)(next)
      Error(reason) -> Error(reason)
    }
  }
}
