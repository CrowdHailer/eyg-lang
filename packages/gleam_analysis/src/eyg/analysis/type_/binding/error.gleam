import eyg/analysis/type_/binding
import eyg/ir/tree as ir
import gleam/list

pub type Reason {
  Todo
  MissingVariable(String)
  MissingBuiltin(String)
  MissingReference(reference: ir.Reference)
  TypeMismatch(binding.Mono, binding.Mono)
  MissingRow(String)
  Recursive
  SameTail(binding.Mono, binding.Mono)
}

/// Resolves the types embedded in a diagnostic using the retained bindings.
pub fn resolve(reason: Reason, bindings) -> Reason {
  case reason {
    TypeMismatch(expected, given) ->
      TypeMismatch(
        binding.resolve(expected, bindings),
        binding.resolve(given, bindings),
      )
    SameTail(expected, given) ->
      SameTail(
        binding.resolve(expected, bindings),
        binding.resolve(given, bindings),
      )
    _ -> reason
  }
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
