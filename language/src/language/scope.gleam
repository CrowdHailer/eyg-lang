import gleam/list
import language/type_.{Constructor, PolyType, Type, Variable}

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
    types: List(#(String, List(Int), List(#(String, List(Type))))),
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

pub fn newtype(scope, type_name, params, constructors) {
  list.fold(
    constructors,
    scope,
    fn(constructor, scope) {
      let #(fn_name, arguments) = constructor
      // Constructor when instantiate will be unifiying to a concrete type
      let new_type = Constructor(type_name, list.map(params, Variable))
      set_variable(
        scope,
        fn_name,
        PolyType(
          forall: params,
          type_: Constructor("Function", list.append(arguments, [new_type])),
        ),
      )
    },
  )
}

// assign and lookup
pub fn get_variable(scope, label) {
  let Scope(variables: variables, ..) = scope
  case list.key_find(variables, label) {
    Ok(value) -> Ok(value)
    Error(Nil) -> Error("Variable not in environment")
  }
}

pub fn get_constructor(scope, constructor) {
  // loop through call
  todo("get_constructor")
}

// fn generalise_type(type_, typer) {
//   case type_ {
//     Function(arguments, return) -> todo("some")
//   }
//   // App(_) -> 
//   // Variable(_) -> []
// }
fn instantiate() {
  todo
}
