import eyg/analysis/type_/binding

pub type Reason {
  MissingVariable(String)
  TypeMismatch(binding.Mono, binding.Mono)
  MissingRow(String)
}
