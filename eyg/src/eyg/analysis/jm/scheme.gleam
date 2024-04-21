import eyg/analysis/jm/type_ as t
import gleam/dict
import gleam/set

pub type Scheme =
  #(List(Int), t.Type)

pub fn ftv(scheme) {
  let #(forall, typ) = scheme
  set.drop(t.ftv(typ), forall)
}

pub fn apply(sub, scheme) {
  let #(forall, typ) = scheme
  #(forall, t.apply(dict.drop(sub, forall), typ))
}
