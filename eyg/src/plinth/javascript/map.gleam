pub external type MutableMap(k, v)

pub external fn new() -> MutableMap(k, v) =
  "../../plinth_ffi.js" "map_new"

pub external fn set(MutableMap(k, v), k, v) -> MutableMap(k, v) =
  "../../plinth_ffi.js" "map_set"

pub external fn get(MutableMap(k, v), k) -> Result(v, Nil) =
  "../../plinth_ffi.js" "map_get"

pub external fn size(MutableMap(k, v)) -> Int =
  "../../plinth_ffi.js" "map_size"
