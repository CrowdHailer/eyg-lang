import gleam/list

pub type E {
  Var(String)
  Let(String)
  Apply
}

pub type T {
  Unbound
}

pub type C {
  E(E)
  T(T)
}

pub type K {
  Assing(label: String)
}

// Doing this quick does a lot of mutable stuff

// pub fn infer(source, eff, state) {
//   list.map_fold(source, todo, fn(acc, exp) {
//     let #(level, var, bindings, eff, store, stack) = acc
//     case exp {
//       Var(x) -> todo
//       Let(x) -> Next([Assign(x, ref)])
//       Binary -> T(Binary, ks)
//     }
//   })
// }

// pub fn typeof(exp, env, acc) {
//   case exp {
//     Var(_) -> {
//       let type_ = todo as "assume found"
//       #(type_, acc)
//     }
//     Apply(fun, arg) -> {
//       // return the inner type value and then I can push a schema to the acc
//       let #(ty_fun, inner) = typeof(fun, env, [])
//       let #(ty_arg, inner) = typeof(arg, env, inner)

//       todo as "unify"
//     }
//     Let(label, value, then) -> {
//       let #(ty_value, inner) = typeof(value, env, [])
//       // Don't pass in acc alg J grows from the bottom
//       // all types is about errors

//       let schema_value = gen(ty_value)
//       // let acc = list.concat(inner, [schema_value, ..acc])
//       // let #(ty_then, inner) = typeof(then, env, [])
//     }
//   }
//   // [Var(label), ..rest] -> #(Ok(1), rest, [])
//   // [Let(label), ..rest] -> #(Ok(1), rest, [Assign(label)])
// }

// TODO test accessing fn param with type defined through the function body
// Do all my tests using parser
// I dont think I have a flatenerin in Gleam

pub fn gen(_) {
  todo
}
// fn(x) {
// let y = x
// y(5)
// y(String)
// }
