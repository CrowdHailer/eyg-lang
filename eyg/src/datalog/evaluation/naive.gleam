import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import datalog/ast

pub type DB =
  Dict(String, List(List(ast.Value)))

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
    _ -> Error(Nil)
  }
}

fn populate(db, facts) {
  case facts {
    [] -> db
    [ast.Atom(relation, terms), ..rest] -> {
      let assert Ok(values) = list.try_map(terms, is_literal)
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
  list.fold(rules, initial, fn(db, rule) {
    let ast.Constraint(head, body) = rule

    let constraints = {
      use #(_negated, ast.Atom(r, patterns)) <- list.flat_map(body)
      use values <- list.map(
        dict.get(initial, r)
        |> result.unwrap([]),
      )
      let assert Ok(pairs) = list.strict_zip(patterns, values)
      pairs
    }
    list.fold(constraints, db, fn(db, constraints) {
      io.debug(constraints)
      let r =
        list.try_fold(constraints, dict.new(), fn(subs, constraint) {
          let #(a, b) = constraint
          unify(a, ast.Literal(b), subs)
        })
      case r {
        Ok(subs) -> {
          dict.update(db, head.relation, fn(previous) {
            let previous = case previous {
              None -> []
              Some(x) -> x
            }
            let values =
              list.map(head.terms, fn(t) {
                case walk(t, subs) {
                  ast.Literal(v) -> v
                  ast.Variable(_l) -> {
                    // let assert Ok(v) = walk(subs, l)
                    // v
                    panic
                  }
                }
              })
            io.debug(values)
            [values, ..previous]
          })
        }
        Error(Nil) -> db
      }
    })
  })
  //   todo
  // let bindings =
  //   list.fold(body, dict.new(), fn(bindings, atom) {
  //     let assert #(False, ast.Atom(relation, terms)) = atom
  //     let values =
  //       dict.get(db, relation)
  //       |> result.unwrap([])

  //   })
}

pub fn run(program) {
  let ast.Program(constraints) = program
  let db: DB = dict.new()

  let #(facts, rules) = do_separate([], [], constraints)
  io.debug(facts)

  let db = populate(db, facts)
  step(db, rules)
  |> io.debug
  //   todo
  //     todo
  //     loop through constraints in program
  //     add to db
  //     if body then match to existing and repeat

  //     flat map with bindings
}
