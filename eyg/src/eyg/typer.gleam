import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eyg/ast.{
  Binary, Call, Case, Constructor, Function, Let, Name, Provider, Row, Tuple, Variable,
}
import eyg/ast/pattern
import eyg/typer/monotype
import eyg/typer/polytype.{State}

// Context/typer
pub type Reason {
  IncorrectArity(expected: Int, given: Int)
  UnknownVariable(label: String)
  UnmatchedTypes(expected: monotype.Monotype, given: monotype.Monotype)
  MissingFields(expected: List(#(String, monotype.Monotype)))
  UnexpectedFields(expected: List(#(String, monotype.Monotype)))
  UnknownType(name: String)
  UnknownVariant(variant: String, in: String)
  DuplicateType(name: String)
  RedundantClause(match: String)
  UnhandledVariants(remaining: List(String))
}

pub fn init(variables) {
  State(variables, 0, [], [], [])
}

fn add_substitution(variable, resolves, typer) {
  let State(substitutions: substitutions, ..) = typer
  let substitutions = [#(variable, resolves), ..substitutions]
  State(..typer, substitutions: substitutions)
}

fn unify_pair(pair, typer) {
  let #(expected, given) = pair
  unify(expected, given, typer)
}

// monotype function??
// This will need the checker/unification/constraints data structure as it uses subsitutions and updates the next var value
// next unbound inside mono can be integer and unbound(i) outside
pub fn unify(expected, given, typer) {
  let State(substitutions: substitutions, ..) = typer
  let expected = monotype.resolve(expected, substitutions)
  let given = monotype.resolve(given, substitutions)
  case expected, given {
    monotype.Binary, monotype.Binary -> Ok(typer)
    monotype.Tuple(expected), monotype.Tuple(given) ->
      case list.zip(expected, given) {
        Error(#(expected, given)) ->
          Error(#(IncorrectArity(expected, given), typer))
        Ok(pairs) -> list.try_fold(pairs, typer, unify_pair)
      }
    monotype.Unbound(i), any -> Ok(add_substitution(i, any, typer))
    any, monotype.Unbound(i) -> Ok(add_substitution(i, any, typer))
    monotype.Row(expected, expected_extra), monotype.Row(given, given_extra) -> {
      let #(expected, given, shared) = group_shared(expected, given)
      let #(x, typer) = polytype.next_unbound(typer)
      try typer = case given, expected_extra {
        [], _ -> Ok(typer)
        only, Some(i) ->
          Ok(add_substitution(i, monotype.Row(only, Some(x)), typer))
        only, None -> Error(#(UnexpectedFields(only), typer))
      }
      try typer = case expected, given_extra {
        [], _ -> Ok(typer)
        only, Some(i) ->
          Ok(add_substitution(i, monotype.Row(only, Some(x)), typer))
        only, None -> Error(#(MissingFields(only), typer))
      }
      list.try_fold(shared, typer, unify_pair)
    }
    monotype.Nominal(expected_name, expected_parameters), monotype.Nominal(
      given_name,
      given_parameters,
    ) -> {
      try _ = case expected_name == given_name {
        True -> Ok(Nil)
        False -> Error(#(UnmatchedTypes(expected, given), typer))
      }
      case list.zip(expected_parameters, given_parameters) {
        Error(#(_expected, _given)) ->
          todo("I don't think we should ever fail here")
        Ok(pairs) -> list.try_fold(pairs, typer, unify_pair)
      }
    }
    monotype.Function(expected_from, expected_return), monotype.Function(
      given_from,
      given_return,
    ) -> {
      try typer = unify(expected_from, given_from, typer)
      unify(expected_return, given_return, typer)
    }
    expected, given -> Error(#(UnmatchedTypes(expected, given), typer))
  }
}

fn group_shared(left, right) {
  do_group_shared(left, right, [], [])
}

fn do_group_shared(left, right, only_left, shared) {
  case left {
    [] -> #(list.reverse(only_left), right, list.reverse(shared))
    [#(k, left_value), ..left] ->
      case list.key_pop(right, k) {
        Ok(#(right_value, right)) -> {
          let shared = [#(left_value, right_value), ..shared]
          do_group_shared(left, right, only_left, shared)
        }
        Error(Nil) -> {
          let only_left = [#(k, left_value), ..only_left]
          do_group_shared(left, right, only_left, shared)
        }
      }
  }
}

// scope functions
fn get_variable(label, state) {
  let State(variables: variables, ..) = state
  case list.key_find(variables, label) {
    Ok(polytype) -> Ok(polytype.instantiate(polytype, state))
    Error(Nil) -> Error(#(UnknownVariable(label), state))
  }
}

fn set_variable(label, monotype, state) {
  let State(variables: variables, substitutions: substitutions, ..) = state
  let polytype =
    polytype.generalise(monotype.resolve(monotype, substitutions), state)
  let variables = [#(label, polytype), ..variables]
  State(..state, variables: variables, substitutions: substitutions)
}

// assignment/patterns
fn match_pattern(pattern, given, typer) {
  case pattern {
    pattern.Variable(label) -> Ok(set_variable(label, given, typer))
    pattern.Tuple(elements) -> {
      let #(types, typer) =
        list.map_state(
          elements,
          typer,
          // Don't call typer as there is a bug
          fn(label, t) {
            let #(x, t) = polytype.next_unbound(t)
            let type_var = monotype.Unbound(x)
            let t = set_variable(label, type_var, t)
            #(type_var, t)
          },
        )
      let expected = monotype.Tuple(types)
      unify(expected, given, typer)
    }
    pattern.Row(fields) -> {
      let #(typed_fields, typer) =
        list.map_state(
          fields,
          typer,
          fn(field, t) {
            let #(name, label) = field
            let #(x, t) = polytype.next_unbound(t)
            let type_var = monotype.Unbound(x)
            let t = set_variable(label, type_var, t)
            #(#(name, type_var), t)
          },
        )
      let #(x, typer) = polytype.next_unbound(typer)
      let expected = monotype.Row(typed_fields, Some(x))
      unify(expected, given, typer)
    }
  }
}

// inference fns
// fn infer_field(field, typer) {
//   let #(name, tree) = field
//   let #(type_, typer) = infer(tree, typer)
//   // NOTE this assumes infer_field always used in a list.map context TODO remove 999
//   #(#(name, type_), append_path(typer, 999))
// }
fn append_path(typer, i) {
  let State(location: location, ..) = typer
  State(..typer, location: list.append(location, [i]))
}

pub type Metadata {
  Metadata(
    path: List(Int),
    type_: Result(monotype.Monotype, Reason),
    scope: List(#(String, polytype.Polytype)),
  )
}

pub fn get_type(
  tree: ast.Expression(Metadata),
) -> Result(monotype.Monotype, Reason) {
  let #(Metadata(type_: type_, ..), _) = tree
  type_
}

fn do_unify(expected, given, typer) {
  case unify(expected, given, typer) {
    Ok(typer) -> #(Ok(expected), typer)
    // Don't think typer needs returning from unify?
    Error(#(reason, typer)) -> #(Error(reason), typer)
  }
}

fn pairs_second(pair: #(a, b)) -> b {
  pair.1
}

fn with_unbound(thing, typer) {
  let #(x, typer) = polytype.next_unbound(typer)
  let type_ = monotype.Unbound(x)
  #(#(thing, type_), typer)
}

pub fn infer(
  expression: ast.Expression(Nil),
  expected: monotype.Monotype,
  typer: State,
) -> #(ast.Expression(Metadata), State) {
  // return all context so more info can be added later
  let #(_, tree) = expression
  let State(location: path, ..) = typer
  let meta = Metadata(path: path, type_: _, scope: typer.variables)
  case tree {
    Binary(value) -> {
      let #(type_, typer) = do_unify(expected, monotype.Binary, typer)
      let expression = #(meta(type_), Binary(value))
      #(expression, typer)
    }
    Tuple(elements) -> {
      let #(pairs, typer) = list.map_state(elements, typer, with_unbound)
      let given = monotype.Tuple(list.map(pairs, pairs_second))
      let #(type_, typer) = do_unify(expected, given, typer)
      // decided I want to match on top level first
      let #(elements, #(typer, _)) =
        list.map_state(
          pairs,
          #(typer, 0),
          fn(pair, stz) {
            let #(tz, i) = stz
            let #(element, expected) = pair
            let tz = State(..tz, location: ast.append_path(path, i))
            let #(element, tz) = infer(element, expected, tz)
            #(element, #(tz, i + 1))
          },
        )
      let expression = #(meta(type_), Tuple(elements))
      #(expression, typer)
    }
    Row(fields) -> {
      let #(pairs, typer) = list.map_state(fields, typer, with_unbound)
      let given =
        monotype.Row(
          list.map(
            pairs,
            fn(pair) {
              let #(#(name, _value), type_) = pair
              #(name, type_)
            },
          ),
          None,
        )
      // TODO don't think returning type_ needed
      let #(type_, typer) = do_unify(expected, given, typer)
      let #(fields, #(typer, _)) =
        list.map_state(
          pairs,
          #(typer, 0),
          fn(pair, stz) {
            let #(tz, i) = stz
            let #(#(name, value), expected) = pair
            let tz = State(..tz, location: ast.append_path(path, i))
            let #(value, tz) = infer(value, expected, tz)
            #(#(name, value), #(tz, i + 1))
          },
        )
      let expression = #(meta(type_), Row(fields))
      #(expression, typer)
    }
  }
  //   let #(trees, typer) = list.map_state(fields, typer, infer_field)
  //   let types =
  //     list.map(
  //       trees,
  //       fn(tree_with_other_name) {
  //         let #(name, #(Metadata(type_: Ok(type_), ..), _)) =
  //           tree_with_other_name
  //         #(name, type_)
  //       },
  //     )
  //   let type_ = monotype.Row(types, None)
  //   #(#(meta(Ok(type_)), Row(trees)), typer)
  // Variable(label) ->
  //   case get_variable(label, typer) {
  //     Ok(#(type_, typer)) -> #(#(meta(Ok(type_)), Variable(label)), typer)
  //     Error(#(reason, _)) -> #(#(meta(Error(reason)), Variable(label)), typer)
  //   }
  // Let(pattern, value, then) -> {
  //   let State(location: location, ..) = typer
  //   // TODO remove this nesting when we(if?) separate typer and scope
  //   let State(variables: variables, ..) = typer
  //   let #(value, typer) = infer(value, append_path(typer, 0))
  //   let #(given, typer) = case get_type(value) {
  //     Ok(given) -> #(given, typer)
  //     Error(_) -> {
  //       let #(x, typer) = polytype.next_unbound(typer)
  //       #(monotype.Unbound(x), typer)
  //     }
  //   }
  //   let typer = State(..typer, variables: variables)
  //   case match_pattern(pattern, given, typer) {
  //     Ok(typer) -> {
  //       // same rule as scope needs reseting
  //       let typer = State(..typer, location: location)
  //       let #(then, typer) = infer(then, append_path(typer, 1))
  //       let #(then_type, typer) = case get_type(then) {
  //         Ok(t) -> #(t, typer)
  //         Error(_) -> {
  //           let #(x, typer) = polytype.next_unbound(typer)
  //           #(monotype.Unbound(x), typer)
  //         }
  //       }
  //       let tree = Let(pattern, value, then)
  //       #(#(meta(Ok(then_type)), tree), typer)
  //     }
  //     Error(#(reason, typer)) -> {
  //       // all the variables in the pattern should be added to scope TODO
  //       let typer = State(..typer, location: location)
  //       let #(then, typer) = infer(then, append_path(typer, 1))
  //       let tree = Let(pattern, value, then)
  //       #(#(meta(Error(reason)), tree), typer)
  //     }
  //   }
  // }
  // Function(label, body) -> {
  //   let #(x, typer) = polytype.next_unbound(typer)
  //   let type_var = monotype.Unbound(x)
  //   // TODO remove this nesting when we(if?) separate typer and scope
  //   let State(variables: variables, location: location, ..) = typer
  //   let typer = set_variable(label, type_var, typer)
  //   let #(return, typer) = infer(body, append_path(typer, 0))
  //   let typer = State(..typer, variables: variables, location: location)
  //   // There are ALOT more type variables if handling all the errors.
  //   let Ok(return_type) = get_type(return)
  //   let type_ = monotype.Function(type_var, return_type)
  //   #(#(meta(Ok(type_)), Function(label, return)), typer)
  // }
  // Call(function, with) -> {
  //   let State(location: location, ..) = typer
  //   let #(function, typer) = infer(function, append_path(typer, 0))
  //   let typer = State(..typer, location: location)
  //   let #(with, typer) = infer(with, append_path(typer, 1))
  //   let typer = State(..typer, location: location)
  //   let #(x, typer) = polytype.next_unbound(typer)
  //   let return_type = monotype.Unbound(x)
  //   let #(ftype, typer) = case get_type(function) {
  //     Ok(type_) -> #(type_, typer)
  //     Error(_) -> {
  //       let #(x, typer) = polytype.next_unbound(typer)
  //       #(monotype.Unbound(x), typer)
  //     }
  //   }
  //   let #(with_type, typer) = case get_type(with) {
  //     Ok(type_) -> #(type_, typer)
  //     Error(_) -> {
  //       let #(x, typer) = polytype.next_unbound(typer)
  //       #(monotype.Unbound(x), typer)
  //     }
  //   }
  //   case unify(ftype, monotype.Function(with_type, return_type), typer) {
  //     Ok(typer) -> #(#(meta(Ok(return_type)), Call(function, with)), typer)
  //     Error(#(reason, typer)) -> #(
  //       #(meta(Error(reason)), Call(function, with)),
  //       typer,
  //     )
  //   }
  // }
  // Name(new_type, then) -> {
  //   let #(named, _construction) = new_type
  //   let State(nominal: nominal, ..) = typer
  //   let #(add_name, typer) = case list.key_find(nominal, named) {
  //     Error(Nil) -> {
  //       let typer = State(..typer, nominal: [new_type, ..nominal])
  //       #(Ok(Nil), typer)
  //     }
  //     Ok(_) -> #(Error(DuplicateType(named)), typer)
  //   }
  //   let #(then, typer) = infer(then, append_path(typer, 0))
  //   let tree = Name(new_type, then)
  //   let type_ = case add_name {
  //     Ok(Nil) -> get_type(then)
  //     Error(reason) -> Error(reason)
  //   }
  //   #(#(meta(type_), tree), typer)
  // }
  // Constructor(named, variant) -> {
  //   let State(nominal: nominal, ..) = typer
  //   let #(type_, typer) = case list.key_find(nominal, named) {
  //     Error(Nil) -> #(Error(UnknownType(named)), typer)
  //     Ok(#(parameters, variants)) ->
  //       case list.key_find(variants, variant) {
  //         Error(Nil) -> #(Error(UnknownVariant(variant, named)), typer)
  //         Ok(argument) -> {
  //           // The could be generated in the name phase
  //           let polytype =
  //             polytype.Polytype(
  //               parameters,
  //               monotype.Function(
  //                 argument,
  //                 monotype.Nominal(
  //                   named,
  //                   list.map(parameters, monotype.Unbound),
  //                 ),
  //               ),
  //             )
  //           let #(monotype, typer) = polytype.instantiate(polytype, typer)
  //           #(Ok(monotype), typer)
  //         }
  //       }
  //   }
  //   let tree = #(meta(type_), Constructor(named, variant))
  //   #(tree, typer)
  // }
  // Case(named, subject, clauses) -> {
  //   let State(nominal: nominal, location: location, variables: variables, ..) =
  //     typer
  //   let #(subject, typer) = infer(subject, typer)
  //   let typer = State(..typer, location: location, variables: variables)
  //   let #(x, typer) = polytype.next_unbound(typer)
  //   let return_type = monotype.Unbound(x)
  //   let #(clauses, typer) =
  //     list.map_state(
  //       clauses,
  //       typer,
  //       fn(clause, t) {
  //         let #(variant, variable, then) = clause
  //         let t = State(..t, location: location, variables: variables)
  //         let #(x, t) = polytype.next_unbound(t)
  //         let argument_type = monotype.Unbound(x)
  //         let t = set_variable(variable, argument_type, t)
  //         let #(then, t) = infer(then, t)
  //         let maybe_typer =
  //           case get_type(then) {
  //             Ok(then_type) -> unify(return_type, then_type, t)
  //             _ -> Ok(t)
  //           }
  //           |> io.debug
  //         io.debug("doooooooooo")
  //         io.debug(return_type)
  //         case maybe_typer {
  //           Ok(t) -> {
  //             let clause = #(variant, variable, then)
  //             #(clause, t)
  //           }
  //           Error(reason) -> {
  //             io.debug(reason)
  //             todo("handle mismatched clause")
  //           }
  //         }
  //       },
  //     )
  //   let #(type_, typer) = case list.key_find(nominal, named) {
  //     Error(Nil) -> #(Error(UnknownType(named)), typer)
  //     Ok(#(parameters, variants)) -> {
  //       let #(replacements, typer) =
  //         list.map_state(
  //           parameters,
  //           typer,
  //           fn(parameter, tttj) {
  //             let #(replacement, tttj) = polytype.next_unbound(tttj)
  //             let pair = #(parameter, replacement)
  //             #(pair, tttj)
  //           },
  //         )
  //       let expected =
  //         pair_replace(
  //           replacements,
  //           monotype.Nominal(named, list.map(parameters, monotype.Unbound)),
  //         )
  //       case get_type(subject) {
  //         Ok(subject_type) ->
  //           case unify(expected, subject_type, typer) {
  //             Ok(typer) -> {
  //               ""
  //               // list.map_state(clauses, typer, fn(clause, typer))
  //               #(Ok(return_type), typer)
  //             }
  //           }
  //       }
  //     }
  //   }
  //   // Error(reason) -> Error(reason)
  //   let tree = Case(named, subject, clauses)
  //   #(#(meta(type_), tree), typer)
  // }
  // //     // Think the old version errored by instantiating everytime
  // //       let State(location: location, ..) = typer
  // //       try typer = 
  // //       let State(variables: variables, ..) = typer
  // //       try #(clauses, #(unhandled, typer)) =
  // //         list.try_map_state(
  // //           clauses,
  // //           #(variants, typer),
  // //           // This is an error caused when the name typer is used.
  // //           fn(clause, state) { // Step on earlier because 0 index is subject
  // //             // let typer = step_on_location(typer)
  // //             let #(remaining, t) = state
  // //             try #(argument, remaining) = case list.key_pop(
  // //               remaining,
  // //               variant,
  // //             ) {
  // //               Ok(value) -> Ok(value)
  // //               Error(Nil) ->
  // //                 case list.key_find(variants, variant) {
  // //                   Ok(_) -> Error(#(RedundantClause(variant), typer))
  // //                   Error(Nil) ->
  // //                     Error(#(UnknownVariant(variant, named), typer))
  // //                 }
  // //             }
  // //             let argument = pair_replace(replacements, argument)
  // //             // reset scope variables
  // //             Ok(#(clause, #(remaining, t))) },
  // //         )
  // //       case unhandled {
  // //         [] -> {
  // //           let tree = Case(named, subject, clauses)
  // //           #(#(meta(Ok(return_type)), tree), typer)
  // //         }
  // //       }
  // //     }
  // //   }
  // // }
  // // _ ->
  // //   Error(#(
  // //     UnhandledVariants(list.map(
  // //       unhandled,
  // //       fn(variant) {
  // //         let #(variant, _) = variant
  // //         variant
  // //       },
  // //     )),
  // //     State(..typer, location: location),
  // //   ))
  // // Can't call the generator here because we don't know what the type will resolve to yet.
  // Provider(id, generator) -> {
  //   let type_ = monotype.Unbound(id)
  //   #(#(meta(Ok(type_)), Provider(id, generator)), typer)
  // }
}

fn pair_replace(replacements, monotype) {
  list.fold(
    replacements,
    monotype,
    fn(pair, monotype) {
      let #(x, y) = pair
      polytype.replace_variable(monotype, x, y)
    },
  )
}
