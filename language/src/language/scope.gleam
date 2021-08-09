import gleam/io
import gleam/list
import language/type_.{Data, Function, PolyType, UnknownVariable, Variable}

pub opaque type Scope {
  Scope(variables: List(#(String, PolyType)))
}

pub fn new() {
  Scope(variables: [])
}

fn count_keys(list, key) {
  list.fold(
    list,
    0,
    fn(pair, count) {
      case pair {
        #(k, _) if k == key -> count + 1
        _ -> count
      }
    },
  )
}

pub fn set_variable(scope, label, type_) {
  let Scope(variables: variables) = scope
  let variables = [#(label, type_), ..variables]
  #(
    Scope(..scope, variables: variables),
    #(label, count_keys(variables, label)),
  )
}

// Free vars in forall are those vars that are free
// in the type minus those bound by quantifiers
pub fn free_variables(scope) {
  let Scope(variables: variables) = scope
  list.map(
    variables,
    fn(entry) {
      let #(_name, poly) = entry
      type_.free_variables(poly)
    },
  )
  |> list.fold([], fn(more, acc) { list.append(more, acc) })
}

// assign and lookup
pub fn get_variable(scope, label) {
  let Scope(variables: variables) = scope
  case list.key_find(variables, label) {
    Ok(value) -> Ok(#(value, count_keys(variables, label)))
    Error(Nil) -> Error(UnknownVariable(label))
  }
}

pub fn with_equal(scope) {
  assert #(scope, #("equal", 1)) =
    scope
    |> set_variable(
      "equal",
      PolyType([1], Function([Variable(1), Variable(1)], Data("Boolean", []))),
    )
  scope
}
