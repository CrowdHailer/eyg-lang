import gleam/dynamic.{Dynamic}

pub external fn dynamic_function(
  Dynamic,
) -> Result(fn(Dynamic) -> Result(Dynamic, String), List(dynamic.DecodeError)) =
  "./gleam_extra.js" "dynamic_function"
