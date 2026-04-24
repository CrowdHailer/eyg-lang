import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast

pub const label = "Abort"

pub fn lift() {
  t.String
}

pub fn lower() {
  t.Never
}

pub const decode = cast.as_string
