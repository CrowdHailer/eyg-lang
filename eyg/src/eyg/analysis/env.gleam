import gleam/dict.{type Dict}
import gleam/set
import eyg/analysis/scheme.{type Scheme}

type TypeEnv =
  Dict(String, Scheme)

pub fn empty() {
  dict.new()
}

// TypeEnv
pub fn ftv(env: TypeEnv) {
  dict.fold(env, set.new(), fn(state, _k, scheme) {
    set.union(state, scheme.ftv(scheme))
  })
}

pub fn apply(sub, env) {
  dict.map_values(env, fn(_k, scheme) { scheme.apply(sub, scheme) })
}
