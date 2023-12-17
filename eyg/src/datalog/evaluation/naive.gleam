import gleam/io
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import datalog/ast

pub type DB =
  Dict(String, List(List(ast.Value)))

pub type Reason {
  UnboundVariable(label: String)
}

// inference should be row types against the name. facts are closed and bodys are open
// not much unification if the head is also an open row. do we want all fields to be the same. probably
// loop through query

// TODO test with single constant
// Test with single interation
// Test with single recursion
// stratification then negation

fn do_separate(facts, rules, constraints) {
  case constraints {
    [constraint, ..rest] ->
      case constraint {
        ast.Constraint(head, []) -> {
          let facts = [head, ..facts]
          do_separate(facts, rules, rest)
        }
        _ -> {
          let rules = [constraint, ..rules]
          do_separate(facts, rules, rest)
        }
      }
    [] -> #(list.reverse(facts), list.reverse(rules))
  }
}

fn is_literal(term) {
  case term {
    ast.Literal(value) -> Ok(value)
    ast.Variable(var) -> Error(UnboundVariable(var))
  }
}

fn populate(db, facts) {
  case facts {
    [] -> Ok(db)
    [ast.Atom(relation, terms), ..rest] -> {
      use values <- result.then(list.try_map(terms, is_literal))
      let db =
        dict.update(db, relation, fn(found) {
          let previous = case found {
            None -> []
            Some(x) -> x
          }
          [values, ..previous]
        })
      populate(db, rest)
    }
  }
}

fn unify(a: ast.Term, b: ast.Term, substitutions) {
  case walk(a, substitutions), walk(b, substitutions) {
    // Covers variable and constant case
    a, b if a == b -> Ok(substitutions)
    ast.Variable(x), other | other, ast.Variable(x) ->
      Ok(dict.insert(substitutions, x, other))
    _, _ -> Error(Nil)
  }
}

pub fn walk(term, subs) -> ast.Term {
  case term {
    ast.Variable(x) ->
      case dict.get(subs, x) {
        Ok(term) -> walk(term, subs)
        Error(Nil) -> term
      }
    ast.Literal(_) -> term
  }
}

pub fn step(initial, rules) {
  list.try_fold(rules, initial, fn(db, rule) {
    let ast.Constraint(head, body) = rule
    // name all the stepss

    let constraints = {
      use #(_negated, ast.Atom(r, patterns)) <- list.flat_map(body)
      use values <- list.map(
        dict.get(initial, r)
        |> result.unwrap([]),
      )
      let assert Ok(pairs) = list.strict_zip(patterns, values)
      io.debug(pairs)
      pairs
    }
    io.debug(constraints)
    list.try_fold(constraints, db, fn(db, constraints) {
      let r =
        list.try_fold(constraints, dict.new(), fn(subs, constraint) {
          let #(a, b) = constraint
          unify(a, ast.Literal(b), subs)
        })
      case r {
        Ok(subs) -> {
          let values =
            list.try_map(head.terms, fn(t) {
              case walk(t, subs) {
                ast.Literal(v) -> Ok(v)
                ast.Variable(var) -> Error(UnboundVariable(var))
              }
            })
          case values {
            Ok(values) ->
              Ok(
                dict.update(db, head.relation, fn(previous) {
                  let previous = case previous {
                    None -> []
                    Some(x) -> x
                  }

                  [values, ..previous]
                }),
              )
            Error(reason) -> Error(reason)
          }
        }
        Error(Nil) -> Ok(db)
      }
    })
  })
}

pub fn run(program) {
  let ast.Program(constraints) = program
  let db: DB = dict.new()

  let #(facts, rules) = do_separate([], [], constraints)
  // io.debug(facts)

  use db <- result.then(populate(db, facts))
  step(db, rules)
  // |> io.debug
  //   todo
  //     todo
  //     loop through constraints in program
  //     add to db
  //     if body then match to existing and repeat

  //     flat map with bindings
}
