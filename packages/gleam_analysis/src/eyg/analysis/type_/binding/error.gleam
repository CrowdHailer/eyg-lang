import eyg/analysis/type_/binding
import gleam/list
import multiformats/cid/v1

pub type Reason {
  Todo
  MissingVariable(String)
  MissingBuiltin(String)
  MissingReference(v1.Cid)
  UndefinedRelease(package: String, release: Int, module: v1.Cid)
  TypeMismatch(binding.Mono, binding.Mono)
  MissingRow(String)
  /// A record is a map from label to value, so a record type that names the
  /// same label twice describes a value that cannot exist.
  DuplicateRow(String)
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
