pub type Control {
  E(List(Expression))
}

pub type Expression {
  Var
  Lambda(String)
  Apply
  Let(String)
}

pub type K {
  DoArg(env: Nil)
  DoApply
  DoAssign(label: String, env: Nil)
}

pub fn function_name() -> Nil {
  todo
}

pub fn step() {
  todo
}
// this is not about being fast, it's ergonomic with linear thing
// is there a CEK style fast J but with recursive data
// the fast J uses a recursvie data structure and builds a linear list of info
// this might be slow because of list copying
// Using a tree data structure but linear output might be good.
// The parser creates stuff and then can be dumped to simple tree with assoc list
// A map of indexed metadata to a value (live or types) might be faster
// type inference works with a fold, perhaps a map fold to go through building something up
// means putting type vars you don't know
// Need to do my version of live loop
// works with metadata in tree otherwise a building of path
// if using tree data structure not easy to track index and use array
// path is better arbitrary meta data might not be unique

// if already zipped linear is hardly better as I have a meta var I need to pass around
// I think cek can return a Value case without an env.
// dont want to recursivly apply or eval as both might blow JS stack
// I don't tihnk fast_J is fast with all my list building
// fn evalpc(pc, env, k) {
//   //   let assert [exp, ..rest] = exp
//   let assert Ok(exp) = todo
//   case exp {
//     // update program counter outside state
//     Lambda(x) -> #(#(pc + size(pc + 1), Closure(x, pc + 1, env)), env, k)
//     // if apply on function don't make a closure, is there a rusty way to track no new allocation
//     Apply -> #(#(rest), env, DoArg(env))
//     Let(x) -> #(#(rest), env, DoAssign(x, env))
//   }
// }

// fn eval(exp, env, k) {
//   let assert [exp, ..rest] = exp
//   case exp {
//     Lambda(x) -> todo as "increase pc"
//     // if apply on function don't make a closure, is there a rusty way to track no new allocation
//     Apply -> #(E(rest), env, DoArg(env))
//     Let(x) -> #(E(rest), env, DoAssign(x, env))
//   }
// }
