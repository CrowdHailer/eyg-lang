import gleam/string as str
import harness/ffi/spec.{build, integer, lambda, string}

pub fn append() {
  lambda(string(), lambda(string(), string()))
  |> build(fn(x) { fn(y) { str.append(x, y) } })
}

pub fn uppercase() {
  lambda(string(), string())
  |> build(fn(x) { str.uppercase(x) })
}

pub fn lowercase() {
  lambda(string(), string())
  |> build(fn(x) { str.lowercase(x) })
}

pub fn length() {
  lambda(string(), integer())
  |> build(fn(x) { str.length(x) })
}
