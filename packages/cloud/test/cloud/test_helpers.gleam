import cloud/beam/execute
import eyg/hub/cache
import gleam/option.{None}
import ogre/origin

pub fn state() {
  let assert Ok(origin) = origin.from_string_strict("https://eyg.run")
  execute.State(origin:, cache: cache.ready(), root: None)
}
