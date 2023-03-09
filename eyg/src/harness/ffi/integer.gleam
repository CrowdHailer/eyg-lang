import gleam/int
import eyg/runtime/interpreter as r
import harness/ffi/cast

pub fn add() {
  r.Arity2(do_add)
}

fn do_add(left, right, _builtins, k) {
  use left <- cast.integer(left)
  use right <- cast.integer(right)
  r.continue(k, r.Integer(left + right))
}

pub fn subtract() {
  r.Arity2(do_subtract)
}

fn do_subtract(left, right, _builtins, k) {
  use left <- cast.integer(left)
  use right <- cast.integer(right)
  r.continue(k, r.Integer(left - right))
}

pub fn multiply() {
  r.Arity2(do_multiply)
}

fn do_multiply(left, right, _builtins, k) {
  use left <- cast.integer(left)
  use right <- cast.integer(right)
  r.continue(k, r.Integer(left * right))
}

pub fn divide() {
  r.Arity2(do_divide)
}

fn do_divide(left, right, _builtins, k) {
  use left <- cast.integer(left)
  use right <- cast.integer(right)
  r.continue(k, r.Integer(left / right))
}

pub fn absolute() {
  r.Arity1(do_absolute)
}

fn do_absolute(x, _builtins, k) {
  use x <- cast.integer(x)
  r.continue(k, r.Integer(int.absolute_value(x)))
}

pub fn parse() {
  r.Arity1(do_parse)
}

fn do_parse(raw, _builtins, k) {
  use raw <- cast.string(raw)
  case int.parse(raw) {
    Ok(i) -> r.ok(r.Integer(i))
    Error(Nil) -> r.error(r.unit)
  }
  |> r.continue(k, _)
}

pub fn to_string() {
  r.Arity1(do_to_string)
}

fn do_to_string(x, _builtins, k) {
  use x <- cast.integer(x)
  r.continue(k, r.Binary(int.to_string(x)))
}
