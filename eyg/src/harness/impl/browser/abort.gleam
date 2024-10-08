import eyg/analysis/type_/isomorphic as t
import eyg/runtime/break
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/javascript/promise
import gleam/result
import plinth/javascript/date

pub const l = "Abort"

pub const lift = t.String

pub const reply = t.unit

pub fn type_() {
  #(l, #(lift, reply))
}

pub fn blocking(lift) {
  //   use value <- result.map(impl(lift))
  Error(break.UnhandledEffect("Abort", lift))
}
