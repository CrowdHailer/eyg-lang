import gleam/map.{Map}
import gleam/set
import eyg/analysis/scheme.{Scheme}

type TypeEnv =
  Map(String, Scheme)

pub fn empty() {
  map.new()
}

// TypeEnv
pub fn ftv(env: TypeEnv) {
  map.fold(
    env,
    set.new(),
    fn(state, _k, scheme) { set.union(state, scheme.ftv(scheme)) },
  )
}

pub fn apply(sub, env) {
  map.map_values(env, fn(_k, scheme) { scheme.apply(sub, scheme) })
}
