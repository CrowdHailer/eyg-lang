import gleam/io
import gleam/list
import language/type_.{Data, Function, PolyType, Type, UnknownVariable, Variable}

// pub type Type {
//   Function(arguments: List(Type), return: Type)
//   App(name: String, parameters: List(Type))
//   Variable(Int)
// }
pub opaque type Scope {
  // varibles are polytype in one thing
  Scope(
    // Maybe remove polytype
    variables: List(#(String, PolyType)),
    // variables: List(#(String, #(List(Int), Type))),
    // called datatypes from haskell
    // forall a, Some(a) -> Option(a)
    // #(name, parameters, constructors(name, arguments))
    // This is a polytype for n-things
    types: List(#(String, #(List(Int), List(#(String, List(Type)))))),
  )
}

// types: List(Nil)
pub fn new() {
  Scope([], [])
}

pub fn set_variable(scope, label, type_) {
  let Scope(variables: variables, ..) = scope
  let variables = [#(label, type_), ..variables]
  Scope(..scope, variables: variables)
}

// Free vars in forall are those vars that are free
// in the type minus those bound by quantifiers
pub fn free_variables(scope) {
  let Scope(variables: variables, ..) = scope
  list.map(
    variables,
    fn(entry) {
      let #(_name, poly) = entry
      type_.free_variables(poly)
    },
  )
  |> list.fold([], fn(more, acc) { list.append(more, acc) })
}

external fn log(a) -> Nil =
  "" "console.log"

pub fn newtype(scope, type_name, params, constructors) {
  let Scope(types: types, ..) = scope
  let types = [#(type_name, #(params, constructors)), ..types]
  let scope = Scope(..scope, types: types)
  // There is a bug in this fold implementation in JS
  // let x = list.fold(
  //   constructors,
  //   scope,
  //   fn(constructor, scope) {
  //     log("--------")
  //     log(scope)
  //     let #(fn_name, arguments) = constructor
  //     // Constructor when instantiate will be unifiying to a concrete type
  //     let new_type = Data(type_name, list.map(params, Variable))
  //     let n = set_variable(
  //       scope,
  //       fn_name,
  //       PolyType(forall: params, type_: Function(arguments, new_type)),
  //     )
  //     log(n)
  //     log(constructor)
  //     log("--========")
  //     n
  //   },
  // )
  // log("end")
  // x
  add_constructors(scope, constructors, type_name, params)
}

fn add_constructors(scope, constructors, type_name, params) {
  case constructors {
    [] -> scope
    [#(fn_name, arguments), ..rest] -> {
      let new_type = Data(type_name, list.map(params, Variable))
      let scope =
        set_variable(
          scope,
          fn_name,
          PolyType(forall: params, type_: Function(arguments, new_type)),
        )
      add_constructors(scope, rest, type_name, params)
    }
  }
}

// assign and lookup
pub fn get_variable(scope, label) {
  let Scope(variables: variables, ..) = scope
  case list.key_find(variables, label) {
    Ok(value) -> Ok(value)
    Error(Nil) -> Error(UnknownVariable(label))
  }
}

pub fn get_varients(scope, type_name) {
  let Scope(types: types, ..) = scope
  let Ok(#(_params, constructors)) = list.key_find(types, type_name)
  list.map(
    constructors,
    fn(constructor) {
      let #(fn_name, _args) = constructor
      fn_name
    },
  )
}

// pub fn get_constructor(scope, constructor) {
//   let Scope(types: types, ..) = scope
//   do_get_constructor(types, constructor)
// }
// fn do_get_constructor(types, constructor) {
//   case types {
//     // Although in this case it's an unknown constructor
//     [] -> Error(UnknownVariable(constructor))
//     [#(type_name, params, variants), ..types] ->
//       case list.key_find(variants, constructor) {
//         Ok(arguments) -> Ok(#(type_name, params, arguments))
//         Error(Nil) -> do_get_constructor(types, constructor)
//       }
//   }
// }
pub fn with_equal(scope) {
  scope
  |> newtype("Boolean", [], [#("True", []), #("False", [])])
  |> set_variable(
    "equal",
    PolyType([1], Function([Variable(1), Variable(1)], Data("Boolean", []))),
  )
}

pub fn with_foo(scope) {
  scope
  |> newtype("Foo", [], [#("A", []), #("B", []), #("C", [])])
}
