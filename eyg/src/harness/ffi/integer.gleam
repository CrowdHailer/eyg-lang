import gleam/int
import harness/ffi/spec.{
  build, empty, end, integer, lambda, record, string, union, variant,
}

pub fn add() {
  lambda(integer(), lambda(integer(), integer()))
  |> build(fn(x) { fn(y) { x + y } })
}

pub fn subtract() {
  lambda(integer(), lambda(integer(), integer()))
  |> build(fn(x) { fn(y) { x - y } })
}

pub fn multiply() {
  lambda(integer(), lambda(integer(), integer()))
  |> build(fn(x) { fn(y) { x * y } })
}

pub fn divide() {
  lambda(integer(), lambda(integer(), integer()))
  |> build(fn(x) { fn(y) { x / y } })
}

pub fn absolute() {
  lambda(integer(), integer())
  |> build(fn(x) { int.absolute_value(x) })
}

pub fn int_parse() {
  lambda(
    string(),
    union(variant("Ok", integer(), variant("Error", record(empty()), end()))),
  )
  |> build(fn(raw) {
    fn(ok) {
      fn(error) {
        case int.parse(raw) {
          Ok(i) -> ok(i)
          Error(_) -> error(Nil)
        }
      }
    }
  })
}

pub fn int_to_string() {
  lambda(integer(), string())
  |> build(fn(x) { int.to_string(x) })
}
