import gleam/dict
import gleam/set
import eyg/analysis/jm/scheme

pub type Env =
  dict.Dict(String, scheme.Scheme)

fn ftv_for_key(state, _k, scheme) {
  set.union(state, scheme.ftv(scheme))
}

pub fn ftv(env: Env) {
  dict.fold(env, set.new(), ftv_for_key)
}

pub fn apply(sub, env) {
  dict.map_values(env, fn(_k, scheme) { scheme.apply(sub, scheme) })
}
