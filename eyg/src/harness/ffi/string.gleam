import gleam/string
import eyg/runtime/interpreter as r
import harness/ffi/cast

pub fn append() {
  r.Arity2(do_append)
}

pub fn do_append(left, right, k) {
  use left <- cast.string(left)
  use right <- cast.string(right)
  r.continue(k, r.Binary(string.append(left, right)))
}

pub fn uppercase() {
  r.Arity1(do_uppercase)
}

pub fn do_uppercase(value, k) {
  use value <- cast.string(value)
  r.continue(k, r.Binary(string.uppercase(value)))
}

pub fn lowercase() {
  r.Arity1(do_lowercase)
}

pub fn do_lowercase(value, k) {
  use value <- cast.string(value)
  r.continue(k, r.Binary(string.lowercase(value)))
}

pub fn length() {
  r.Arity1(do_length)
}

pub fn do_length(value, k) {
  use value <- cast.string(value)
  r.continue(k, r.Integer(string.length(value)))
}
