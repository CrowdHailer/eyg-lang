import gleam/string
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/cast

pub fn append() {
  let type_ = t.Fun(t.Binary, t.Open(0), t.Fun(t.Binary, t.Open(0), t.Binary))
  #(type_, r.Arity2(do_append))
}

pub fn do_append(left, right, _builtins, k) {
  use left <- cast.string(left)
  use right <- cast.string(right)
  r.continue(k, r.Binary(string.append(left, right)))
}

pub fn uppercase() {
  let type_ = t.Fun(t.Binary, t.Open(0), t.Binary)
  #(type_, r.Arity1(do_uppercase))
}

pub fn do_uppercase(value, _builtins, k) {
  use value <- cast.string(value)
  r.continue(k, r.Binary(string.uppercase(value)))
}

pub fn lowercase() {
  let type_ = t.Fun(t.Binary, t.Open(0), t.Binary)
  #(type_, r.Arity1(do_lowercase))
}

pub fn do_lowercase(value, _builtins, k) {
  use value <- cast.string(value)
  r.continue(k, r.Binary(string.lowercase(value)))
}

pub fn length() {
  let type_ = t.Fun(t.Binary, t.Open(0), t.Integer)
  #(type_, r.Arity1(do_length))
}

pub fn do_length(value, _builtins, k) {
  use value <- cast.string(value)
  r.continue(k, r.Integer(string.length(value)))
}
