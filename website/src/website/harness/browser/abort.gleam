import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/cast

pub const l = "Abort"

pub const lift = t.String

pub const reply = t.Never

pub fn type_() {
  #(l, #(lift, reply))
}

pub fn cast(input) {
  cast.as_string(input)
}

pub fn blocking(lift) {
  //   use value <- result.map(impl(lift))
  Error(break.UnhandledEffect("Abort", lift))
}

pub fn preflight(lift) {
  Error(break.UnhandledEffect("Abort", lift))
}
