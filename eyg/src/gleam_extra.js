import * as G from "./gleam.mjs";

// All of my things are function 1
export function dynamic_function(f) {
  if (typeof f == "function" && f.length == 1) {
    function wrapped(x) {
      try {
        return new G.Ok(f(x));
      } catch (error) {
        return new G.Error(error.toString());
      }
    }
    return new G.Ok(wrapped);
  } else {
    return new G.Error(new G.Empty());
  }
}
