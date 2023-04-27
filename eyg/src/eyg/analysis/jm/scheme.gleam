import gleam/map
import gleam/set
import eyg/analysis/jm/type_ as t

pub type Scheme =
  #(List(Int), t.Type)

pub fn ftv(scheme) {
  let #(forall, typ) = scheme
  set.drop(t.ftv(typ), forall)
}

pub fn apply(sub, scheme) {
  let #(forall, typ) = scheme
  #(forall, t.apply(map.drop(sub, forall), typ))
}
