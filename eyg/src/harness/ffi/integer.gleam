import gleam/int
import harness/ffi/spec.{build, integer, lambda, string}

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
  lambda(integer(), lambda(integer(), integer()))
  |> build(fn(x) { fn(y) { todo("needs result type") } })
}

pub fn int_to_string() {
  lambda(integer(), string())
  |> build(fn(x) { int.to_string(x) })
}
