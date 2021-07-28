import gleam/io
import gleam/list

// TODO name typer
pub type Type {
  Constructor(String, List(Type))
  Variable(Int)
}

pub type PolyType {
  PolyType(forall: List(Int), type_: Type)
}

//   RowType(forall: Int, rows: List(#(String, Type)))
// A linear type on substitutions would ensure passed around
// TODO merge substitutions, need to keep passing next var in typer
// type checker state
pub type Typer {
  Typer(
    // typer passed as globally acumulating set, env is scoped
    substitutions: List(#(Int, Type)),
    next_type_var: Int,
  )
}

pub fn generate_type_var(typer) {
  let Typer(next_type_var: var, ..) = typer
  #(Variable(var), Typer(..typer, next_type_var: var + 1))
}

pub fn unify(t1, t2, typer) {
  case t1, t2 {
    t1, t2 if t1 == t2 -> Ok(typer)
    Variable(i), any -> unify_variable(i, any, typer)
    any, Variable(i) -> unify_variable(i, any, typer)
    Constructor(n1, args1), Constructor(n2, args2) ->
      case n1 == n2 {
        True -> unify_all(args1, args2, typer)
        False -> Error("mismatched constructors")
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
    Constructor(name, args) -> {
        Constructor(name, list.map(args, resolve_type(_, substitutions)))
    }
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
