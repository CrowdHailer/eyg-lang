pub type MutableMap(k, v)

@external(javascript, "../../plinth_ffi.js", "map_new")
pub fn new() -> MutableMap(k, v)

@external(javascript, "../../plinth_ffi.js", "map_set")
pub fn set(a: MutableMap(k, v), b: k, c: v) -> MutableMap(k, v)

@external(javascript, "../../plinth_ffi.js", "map_get")
pub fn get(a: MutableMap(k, v), b: k) -> Result(v, Nil)

@external(javascript, "../../plinth_ffi.js", "map_size")
pub fn size(a: MutableMap(k, v)) -> Int
