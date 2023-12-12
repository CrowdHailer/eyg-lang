import gleam/list
import gleam/dict.{type Dict}

type Value {
  I(Int)
}

type Term {
  Variable(Int)
  Constant(Value)
}

fn i(x) {
  Constant(I(x))
}

type State {
  // note this walks rather than updates on creation
  State(count: Int, substitutions: Dict(Int, Term))
}

fn empty() {
  State(0, dict.new())
}

fn walk(term, subs) {
  case term {
    Variable(x) ->
      case dict.get(subs, x) {
        Ok(term) -> walk(term, subs)
        Error(Nil) -> term
      }
    Constant(_) -> term
  }
}

fn fresh(k) {
  fn(state) {
    let State(count, subs) = state
    k(Variable(count))(State(count + 1, subs))
  }
}

fn unify(u, v, subs) {
  let u = walk(u, subs)
  let v = walk(v, subs)
  case u, v {
    Variable(x), Variable(y) if x == y -> Ok(subs)
    Variable(x), other | other, Variable(x) -> Ok(dict.insert(subs, x, other))
    Constant(x), Constant(y) if x == y -> Ok(subs)
    _, _ -> Error(Nil)
  }
}

fn equal(u, v, k) {
  fn(state) {
    let State(count, subs) = state
    case unify(u, v, subs) {
      Ok(subs) -> k()(State(count, subs))
      Error(Nil) -> []
    }
  }
}

fn or(goals) {
  fn(state) { list.flat_map(goals, fn(g) { g(state) }) }
}

fn done(terms) {
  fn(state: State) { [list.map(terms, walk(_, state.substitutions))] }
}

pub fn kanren_test() {
  let goal = {
    use a <- fresh()
    use b <- fresh()

    use <- equal(a, i(3))
    or([
      {
        use <- equal(a, b)
        done([a, b])
      },
      {
        use <- equal(b, i(7))
        done([a, b])
      },
    ])
  }

  goal(empty())
  Nil
}
