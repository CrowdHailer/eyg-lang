import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}

pub type Pattern {
  // TODO make nested but not to begin with
  Destructure(String, List(String))
  // This should be var but is also a var in expression
  Name(String)
}

// Use opaque type to keep in type information
pub type Expression(t) {
  // Pattern is name in Let
  Let(name: String, value: #(t, Expression(t)), in: #(t, Expression(t)))
  Var(name: String)
  Binary
  // List constructors/patterns
  Case(
    subject: #(t, Expression(t)),
    clauses: List(#(Pattern, #(t, Expression(t)))),
  )
  Tuple
  // arguments are names only
  Function(arguments: List(#(t, String)), body: #(t, Expression(t)))
  Call(function: #(t, Expression(t)), arguments: List(#(t, Expression(t))))
}

// Call this builder
pub fn let_(name, value, in) {
  #(Nil, Let(name, value, in))
}

pub fn var(name) {
  #(Nil, Var(name))
}

pub fn binary() {
  #(Nil, Binary)
}

pub fn case_(subject, clauses) {
  #(Nil, Case(subject, clauses))
}

pub fn function(for, in) {
  #(Nil, Function(map(for, fn(name) { #(Nil, name) }), in))
}

pub fn call(function, with) {
  #(Nil, Call(function, with))
}

// Typed
pub type Type {
  Constructor(String, List(Type))
  Variable(Int)
}

pub type PolyType {
  PolyType(forall: List(Int), type_: Type)
  RowType(forall: Int, rows: List(#(String, Type)))
}

// A linear type on substitutions would ensure passed around
// TODO merge substitutions, need to keep passing next var in typer
// type checker state
type Typer {
  Typer(// tracking names to types
    // environment: List(#(String, Type)),
    // typer passed as globally acumulating set, env is scoped
    substitutions: List(#(Int, Type)), next_type_var: Int)
}

fn generate_type_var(typer) {
  let Typer(next_type_var: var, ..) = typer
  #(Variable(var), Typer(..typer, next_type_var: var + 1))
}

fn push_variable(environment, name, type_) {
  [#(name, type_), ..environment]
}

fn fetch_variable(environment, name) {
  case list.key_find(environment, name) {
    Ok(value) -> Ok(value)
    Error(Nil) -> Error("Variable not in environment")
  }
}

fn push_arguments(untyped, environment, typer) {
  // TODO check double names
  let #(typed, typer) = do_argument_typing(untyped, [], typer)
  let environment = do_push_arguments(typed, environment)
  #(typed, environment, typer)
}

fn do_push_arguments(typed, environment) {
  case typed {
    [] -> environment
    [#(type_, name), ..rest] ->
      do_push_arguments(rest, [#(name, PolyType([], type_)), ..environment])
  }
}

fn do_argument_typing(arguments, typed, typer) {
  case arguments {
    [] -> #(list.reverse(typed), typer)
    [#(Nil, name), ..rest] -> {
      let #(type_, typer) = generate_type_var(typer)
      let typed = [#(type_, name), ..typed]
      do_argument_typing(rest, typed, typer)
    }
  }
}

fn do_typed_arguments_remove_name(
  remaining: List(#(Type, String)),
  accumulator: List(Type),
) -> List(Type) {
  case remaining {
    [] -> list.reverse(accumulator)
    [x, ..rest] -> {
      let #(typed, _name) = x
      do_typed_arguments_remove_name(rest, [typed, ..accumulator])
    }
  }
}

fn typer() {
  Typer([], 10)
  // The new types aren't scoped. if one returns a variable from the env if could clash with parameterised one.
}

pub fn newtype(type_name, params, constructors) -> List(#(String, PolyType)) {
  map(
    constructors,
    fn(constructor) {
      let #(fn_name, arguments) = constructor
      // Constructor when instantiate will be unifiying to a concrete type
      let new_type = Constructor(type_name, map(params, Variable))
      #(
        fn_name,
        PolyType(
          forall: params,
          type_: Constructor("Function", list.append(arguments, [new_type])),
        ),
      )
    },
  )
}

// Polymorphic functions in Gleam not working without annotation
fn test() {
  map([[1, 2], [3, 4]], fn(sublist) { map(sublist, fn(i) { i + 1 }) })
}

fn map(input: List(a), func: fn(a) -> b) -> List(b) {
  do_map(input, func, [])
}

fn do_map(remaining, func, accumulator) {
  case remaining {
    [] -> list.reverse(accumulator)
    [item, ..remaining] -> do_map(remaining, func, [func(item), ..accumulator])
  }
}

pub fn infer(untyped, environment) {
  // TODO case
  let typer = typer()
  try #(type_, tree, typer) = do_infer(untyped, environment, typer)
  let Typer(substitutions: substitutions, ..) = typer
  Ok(#(type_, tree, substitutions))
}

fn free_type_vars_in_type(type_) {
  case type_ {
    Constructor("Function", [Variable(x), Variable(y)]) if x == y -> [y]
    _ -> []
  }
}

fn instantiate(poly_type, typer) {
  let PolyType(forall, type_) = poly_type
  do_instantiate(forall, type_, typer)
}

fn do_instantiate(forall, type_, typer) {
  case forall {
    [] -> #(type_, typer)
    [i, ..rest] -> {
      let #(type_var, typer) = generate_type_var(typer)
      let Constructor(name, arguments) = type_
      let arguments = do_replace_variables(arguments, Variable(i), type_var, [])
      let type_ = Constructor(name, arguments)
      do_instantiate(rest, type_, typer)
    }
  }
}

fn do_replace_variables(arguments, old, new, accumulator) {
  case arguments {
    [] -> list.reverse(accumulator)
    [argument, ..rest] -> {
      let replacement = case argument == old {
        True -> new
        False -> argument
      }
      do_replace_variables(rest, old, new, [replacement, ..accumulator])
    }
  }
}

fn do_infer(untyped, environment, typer) {
  let #(Nil, expression) = untyped
  case expression {
    Binary -> Ok(#(Constructor("Binary", []), Binary, typer))
    Let(name: name, value: value, in: next) -> {
      // TODO remove free variables that all already in the environment as they might get bound later
      // Can I convince myself that all generalisable variables must be above the typer current counter
      // Yes because the environment is passed in and not used again.
      // call this fn generalise when called here.
      try #(value_type, value_tree, typer) = do_infer(value, environment, typer)
      let forall = free_type_vars_in_type(value_type)
      let environment =
        push_variable(environment, name, PolyType(forall, value_type))
      try #(next_type, next_tree, typer) = do_infer(next, environment, typer)
      let tree = Let(name, #(value_type, value_tree), #(next_type, next_tree))
      Ok(#(next_type, tree, typer))
    }
    Var(name) -> {
      try poly_type = fetch_variable(environment, name)
      let #(var_type, typer) = instantiate(poly_type, typer)
      Ok(#(var_type, Var(name), typer))
    }

    // can do silly things like define a function in case subject and use in clause.
    // This would need generalising
    // TODO recursion
    Case(subject, clauses) ->
      case clauses {
        [first, second, ..rest] -> {
          let rest = [second, ..rest]
          try #(subject_type, subject_tree, typer) =
            do_infer(subject, environment, typer)
          let #(first_pattern, first_then) = first
          let Destructure("Some", with) = first_pattern
          let #(typed_with, environment, typer) =
            // This map is because arguments untyped
            push_arguments(
              map(with, fn(name) { #(Nil, name) }),
              environment,
              typer,
            )
          try #(first_type, first_tree, typer) =
            do_infer(first_then, environment, typer)
          list.try_fold(
            rest,
            typer,
            fn(element, typer) {
              let #(pattern, then) = element
              let #(environment, typer) =
                bind_pattern(pattern, subject_type, typer)
              try #(then_type, then_tree, typer) =
                do_infer(then, environment, typer)
              unify(then_type, first_type)
              todo("finish fold, then DO RECURSION")
            },
          )
          let tree = Case(#(subject_type, subject_tree), [])
          Ok(#(first_type, tree, typer))
        }
        _ -> todo("Must be at least two clauses")
      }
    //   // Just name works for True False
    //   let [#(name, then)] = clauses
    //   // add name to environment 
    //   try #(then_type, then_tree, typer) = do_infer(then, environment, typer)
    Function(with, in) -> {
      // There's no lets in arguments that escape the environment so keep reusing initial environment
      let #(typed_with, environment, typer) =
        push_arguments(with, environment, typer)
      try #(in_type, in_tree, typer) = do_infer(in, environment, typer)
      let typed_with: List(#(Type, String)) = typed_with
      let constructor_arguments =
        do_typed_arguments_remove_name(typed_with, [in_type])
      let type_ = Constructor("Function", constructor_arguments)
      let tree = Function(typed_with, #(in_type, in_tree))
      Ok(#(type_, tree, typer))
    }
    // N eed to understand generics but could every typed ast have a variable
    Call(function, with) -> {
      try #(f_type, f_tree, typer) = do_infer(function, environment, typer)
      try #(with_typed, typer) =
        do_infer_call_args(with, environment, typer, [])
      // Think generating the return type is needed for handling recursive.
      let #(return_type, typer) = generate_type_var(typer)
      try typer =
        unify(
          f_type,
          Constructor("Function", append_only_the_type(with_typed, return_type)),
          typer,
        )
      let type_ = return_type
      let tree = Call(#(f_type, f_tree), with_typed)
      Ok(#(type_, tree, typer))
    }
  }
}

pub fn append_only_the_type(before, new) {
  do_append_only_the_type(list.reverse(before), [new])
}

fn do_append_only_the_type(remaining, accumulator) {
  case remaining {
    [] -> accumulator
    [#(type_, tree), ..rest] ->
      do_append_only_the_type(rest, [type_, ..accumulator])
  }
}

fn do_infer_call_args(arguments, environment, typer, accumulator) {
  case arguments {
    [] -> Ok(#(list.reverse(accumulator), typer))
    [untyped, ..rest] -> {
      try #(type_, tree, typer) = do_infer(untyped, environment, typer)
      do_infer_call_args(
        rest,
        environment,
        typer,
        [#(type_, tree), ..accumulator],
      )
    }
  }
}

fn unify(t1, t2, typer) {
  case t1, t2 {
    t1, t2 if t1 == t2 -> Ok(typer)
    Variable(i), any -> unify_variable(i, any, typer)
    any, Variable(i) -> unify_variable(i, any, typer)
    Constructor(n1, args1), Constructor(n2, args2) ->
      case n1 == n2 {
        True -> unify_all(args1, args2, typer)
      }
  }
  // Row(fields, variable), Row(fields, variable) ->
  // case do_shared(left, right, [], []) {
  //   #([], []) -> unify(l_var, r_var)
  //   #(only_left, only_right) -> {
  //     // Need to exit on the case of empy onlyleft and right
  //     // new_var
  //     try unify(Row(only_right, new_var), l_var, typer)
  //     try unify(Row(only_left, new_var), r_var, typer)
  //   }
  // }
}

// do_shared(left, right, shared, only_left) {
//   case left {
//     [] -> list.reverse(only_left), right, shared
//     [#(name, l_type), ..rest] -> case list.key_pop(right, name) {
//       Ok(r_type) -> todo("unify left and right") 
//       Error(Nil) -> do_shared(rest, right_but_popped, shared, [#(name, l_type), ..only_left])
//     }
//   }
// }
// TODO exhausive on guards.
// Pattern is Var(String) || Destructure || RowLookup (Does row lookup work for cases I don't think my types support union on rows.)
fn unify_variable(i, any, typer) {
  let Typer(substitutions: substitutions, ..) = typer
  case list.key_find(substitutions, i) {
    Ok(replacement) -> unify(replacement, any, typer)
    Error(Nil) ->
      case any {
        Variable(j) ->
          case list.key_find(substitutions, i) {
            Ok(replacement) -> unify(replacement, any, typer)
            _ -> {
              let substitutions = [#(i, any), ..substitutions]
              let typer = Typer(..typer, substitutions: substitutions)
              Ok(typer)
            }
          }
        // TODO occurs check
        Constructor(_, _) -> {
          let substitutions = [#(i, any), ..substitutions]
          let typer = Typer(..typer, substitutions: substitutions)
          Ok(typer)
        }
      }
  }
}

fn unify_all(t1s, t2s, typer) {
  case t1s, t2s {
    [], [] -> Ok(typer)
    [t1, ..t1s], [t2, ..t2s] -> {
      try typer = unify(t1, t2, typer)
      unify_all(t1s, t2s, typer)
    }
  }
}

pub fn resolve_type(type_, substitutions) {
  case type_ {
    Constructor(name, args) -> type_
    Variable(i) ->
      case list.key_find(substitutions, i) {
        Ok(Variable(j) as substitution) if i != j ->
          resolve_type(substitution, substitutions)
        Ok(Constructor(_, _) as substitution) ->
          resolve_type(substitution, substitutions)
        _ -> type_
      }
  }
}
