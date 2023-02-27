import gleam/map

pub fn singleton(k, v) {
  map.insert(map.new(), k, v)
}
