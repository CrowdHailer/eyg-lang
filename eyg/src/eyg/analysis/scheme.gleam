import eyg/analysis/substitutions as sub
import eyg/analysis/typ as t
import gleam/set

pub type Scheme {
  Scheme(forall: List(t.Variable), type_: t.Term)
}

pub fn ftv(scheme) {
  let Scheme(forall, typ) = scheme
  set.drop(t.ftv(typ), forall)
}

pub fn apply(sub, scheme) {
  let Scheme(forall, typ) = scheme
  Scheme(forall, sub.apply(sub.drop(sub, forall), typ))
}
