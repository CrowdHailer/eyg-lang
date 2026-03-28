import gleam/dict

pub fn singleton(k, v) {
  dict.insert(dict.new(), k, v)
}
