import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamicx
import gleam/list
import gleam/result

// ast

pub type Term(t) {
  Constant(t)
  Variable(Int)
}

fn dynamify(term) {
  case term {
    Variable(i) -> Variable(i)
    Constant(x) -> Constant(dynamic.from(x))
  }
}

pub type Substitutions =
  Dict(Int, Term(Dynamic))

fn unify(a: Term(t), b: Term(u), substitutions: Substitutions) {
  case walk(dynamify(a), substitutions), walk(dynamify(b), substitutions) {
    // Covers variable and constant case
    a, b if a == b -> Ok(substitutions)
    Variable(x), other | other, Variable(x) ->
      Ok(dict.insert(substitutions, x, dynamify(other)))
    _, _ -> Error(Nil)
  }
}

// exec

pub type State {
  // note this walks rather than updates on creation
  State(count: Int, substitutions: Substitutions)
}

// TODO make private
pub fn walk(term, subs) -> Term(Dynamic) {
  case term {
    Variable(x) ->
      case dict.get(subs, x) {
        Ok(term) -> walk(term, subs)
        Error(Nil) -> term
      }
    Constant(_) -> term
  }
}

pub fn run(q: fn(State) -> List(Result(a, b))) -> Result(List(a), b) {
  list.try_map(q(State(0, dict.new())), fn(r) { r })
}

//queries

pub fn fresh(k) {
  fn(state) {
    let State(count, subs) = state
    k(Variable(count))(State(count + 1, subs))
  }
}

// opposite is match

pub fn not(rule, k) {
  fn(state) {
    case rule(fn() { fn(_state) { [Ok(Nil)] } })(state) {
      [] -> k()(state)
      _ -> []
    }
  }
}

pub fn transform(term: Term(a), f: fn(a) -> b, k) {
  fn(state: State) {
    case walk(dynamify(term), state.substitutions) {
      Constant(x) -> k(Constant(f(dynamicx.unsafe_coerce(x))))(state)
      _ -> panic("should have resolved")
    }
  }
}

fn resolve(term: Term(a), state: State) -> Result(a, Nil) {
  case
    walk(
      dynamicx.unsafe_coerce(dynamic.from(term)),
      dynamicx.unsafe_coerce(dynamic.from(state.substitutions)),
    )
  {
    Constant(value) -> Ok(dynamicx.unsafe_coerce(value))
    Variable(_) -> Error(Nil)
  }
}

pub fn return(term) {
  fn(state: State) { [resolve(term, state)] }
}

pub fn return2(
  a: Term(x),
  b: Term(y),
) -> fn(State) -> List(Result(#(x, y), Nil)) {
  fn(state: State) {
    [
      {
        use a <- result.then(resolve(a, state))
        use b <- result.then(resolve(b, state))
        Ok(#(a, b))
      },
    ]
  }
}

// builders

pub fn facts2(facts) {
  fn(a, b, k) {
    fn(state: State) {
      let context = state.substitutions
      let contexts =
        list.filter_map(facts, fn(fact: #(_, _)) {
          use context <- result.then(unify(a, Constant(fact.0), context))
          use context <- result.then(unify(b, Constant(fact.1), context))
          Ok(context)
        })
      list.flat_map(contexts, fn(c) { k()(State(state.count, c)) })
    }
  }
}
