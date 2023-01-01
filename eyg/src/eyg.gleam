import entry
import gleam/javascript/array.{Array}

// document that rad start shell at dollar
// This becomes the entry point
external fn args(Int) -> Array(String) =
  "" "process.argv.slice"

// zero arity
pub fn main() {
  entry.main(array.to_list(args(1)))
}
