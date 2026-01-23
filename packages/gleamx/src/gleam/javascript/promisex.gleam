import gleam/javascript/promise

pub fn aside(p, k) {
  promise.map(p, k)
  Nil
}

pub fn try_sync(result, then) {
  case result {
    Ok(value) -> then(value)
    Error(reason) -> promise.resolve(Error(reason))
  }
}
