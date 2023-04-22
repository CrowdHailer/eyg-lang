
import gleam/map
import gleam/set
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/scheme

pub type Env = map.Map(String, scheme.Scheme)

fn ftv_for_key(state, _k, scheme) { set.union(state, scheme.ftv(scheme)) }

pub fn ftv(env: Env) {
  map.fold(env, set.new(), ftv_for_key)
}

pub fn apply(sub, env) {
  map.map_values(env, fn(_k, scheme) { scheme.apply(sub, scheme) })
}