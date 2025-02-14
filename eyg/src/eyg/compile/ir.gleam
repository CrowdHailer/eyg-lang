import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/int
import gleam/io
import gleam/list
import gleam/string

// Needs unique variables
pub fn unnest(node) {
  case node {
    #(ir.Let(x, v, t), m) -> {
      let v = unnest(v)
      let t = unnest(t)
      case v {
        #(ir.Let(y, v, i), m1) -> #(ir.Let(y, v, #(ir.Let(x, i, t), m)), m1)
        v -> #(ir.Let(x, v, t), m)
      }
    }
    #(ir.Lambda(x, b), m) -> {
      #(ir.Lambda(x, unnest(b)), m)
    }
    #(ir.Apply(f, a), m) -> {
      case unnest(f), unnest(a) {
        #(ir.Let(x, v, t), ml), a -> #(ir.Let(x, v, #(ir.Apply(t, a), m)), ml)
        f, #(ir.Let(x, v, t), ml) -> #(ir.Let(x, v, #(ir.Apply(f, t), m)), ml)
        f, a -> #(ir.Apply(f, a), m)
      }
    }
    n -> n
  }
}

// a normal
// alpha gives everything a unique name
pub fn alpha(node) {
  do_alpha(node, [], 0).0
}

fn do_alpha(node, env, i) {
  let #(exp, m) = node
  case exp {
    ir.Let(x, value, then) -> {
      let new = string.concat([x, "$", int.to_string(i)])
      let #(value, i) = do_alpha(value, env, i + 1)
      let #(then, i) = do_alpha(then, [#(x, new), ..env], i + 1)
      #(#(ir.Let(new, value, then), m), i)
    }
    ir.Lambda(x, body) -> {
      let new = string.concat([x, "$", int.to_string(i)])
      let #(body, i) = do_alpha(body, [#(x, new), ..env], i + 1)
      #(#(ir.Lambda(new, body), m), i)
    }
    ir.Apply(func, arg) -> {
      let #(func, i) = do_alpha(func, env, i + 1)
      let #(arg, i) = do_alpha(arg, env, i + 1)
      #(#(ir.Apply(func, arg), m), i)
    }
    ir.Variable(x) -> {
      #(
        case list.key_find(env, x) {
          Ok(new) -> #(ir.Variable(new), m)
          Error(Nil) -> node
        },
        i,
      )
    }
    _ -> #(#(exp, m), i)
  }
}

// unwrapped nested Apply
pub fn a_normal() {
  todo
}

// perform Foo([1,2]) Yes
// [perform Foo(1)] No
pub fn k(node) {
  do_k(node, True, 0).0
}

fn do_k(node, safe, i) {
  case node {
    #(ir.Let(x, v, t), m) -> {
      let #(v, i) = do_k(v, True, i)
      let #(t, i) = do_k(t, True, i)
      #(#(ir.Let(x, v, t), m), i)
    }
    #(ir.Lambda(x, b), m) -> {
      let #(b, i) = do_k(b, True, i)
      #(#(ir.Lambda(x, b), m), i)
    }
    #(ir.Apply(f, a), m) -> {
      let #(f, i) = do_k(f, False, i)
      let #(a, i) = do_k(a, False, i)
      let call = #(ir.Apply(f, a), m)
      case m {
        _ if safe == True -> #(call, i)
        t.Empty -> #(call, i)
        _ -> {
          let var = string.append("$k", int.to_string(i))
          #(#(ir.Let(var, call, #(ir.Variable(var), t.Empty)), t.Empty), i + 1)
        }
      }
    }
    other -> #(other, i)
  }
}
// could go to list of lets
// pub fn effect_normal(node) {
//   do_effect_normal(node, k)
// }

// fn do_effect_normal(node, k) {
//   case node {
//     #(ir.Apply(f, a), t.Empty) -> todo
//     #(ir.Apply(f, a), m) -> {
//       let #(f, k) = effect_normal(f, k)
//       let #(a, k) = effect_normal(a, k)
//       //   case k {
//       //     // [Value,.] ->
//       //     // [Then]
//       //   }
//       todo
//     }
//     #(ir.Lambda(x, b), m) -> {
//       let b = effect_normal(node, fn(x) { x })
//       #(ir.Lambda(x, b), m)
//     }
//   }
//   todo
// }
