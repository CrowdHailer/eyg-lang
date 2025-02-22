import eyg/analysis/type_/binding
import gleam/list

pub type Reason {
  Todo
  MissingVariable(String)
  MissingReference(String)
  TypeMismatch(binding.Mono, binding.Mono)
  MissingRow(String)
  Recursive
  SameTail(binding.Mono, binding.Mono)
}

// only looks through errors internal replacements are already in the cache
pub fn missing_references(errors) {
  list.filter_map(errors, fn(error) {
    let #(_path, reason) = error
    case reason {
      MissingReference(ref) -> Ok(ref)
      _ -> Error(Nil)
    }
  })
  |> list.unique()
}
