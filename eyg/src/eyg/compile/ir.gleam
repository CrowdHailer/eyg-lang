import gleam/io
import gleam/int
import gleam/list
import gleam/string
import eyg/analysis/type_/isomorphic as t
import eygir/annotated as a

// Needs unique variables
pub fn unnest(node) {
  case node {
    #(a.Let(x, v, t), m) -> {
      let v = unnest(v)
      let t = unnest(t)
      case v {
        #(a.Let(y, v, i), m1) -> #(a.Let(y, v, #(a.Let(x, i, t), m)), m1)
        v -> #(a.Let(x, v, t), m)
      }
    }
    #(a.Lambda(x, b), m) -> {
      #(a.Lambda(x, unnest(b)), m)
    }
    #(a.Apply(f, a), m) -> {
      case unnest(f), unnest(a) {
        #(a.Let(x, v, t), ml), a -> #(a.Let(x, v, #(a.Apply(t, a), m)), ml)
        f, #(a.Let(x, v, t), ml) -> #(a.Let(x, v, #(a.Apply(f, t), m)), ml)
        f, a -> #(a.Apply(f, a), m)
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
    a.Let(x, value, then) -> {
      let new = string.concat([x, "$", int.to_string(i)])
      let #(value, i) = do_alpha(value, env, i + 1)
      let #(then, i) = do_alpha(then, [#(x, new), ..env], i + 1)
      #(#(a.Let(new, value, then), m), i)
    }
    a.Lambda(x, body) -> {
      let new = string.concat([x, "$", int.to_string(i)])
      let #(body, i) = do_alpha(body, [#(x, new), ..env], i + 1)
      #(#(a.Lambda(new, body), m), i)
    }
    a.Apply(func, arg) -> {
      let #(func, i) = do_alpha(func, env, i + 1)
      let #(arg, i) = do_alpha(arg, env, i + 1)
      #(#(a.Apply(func, arg), m), i)
    }
    a.Variable(x) -> {
      #(
        case list.key_find(env, x) {
          Ok(new) -> #(a.Variable(new), m)
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
    #(a.Let(x, v, t), m) -> {
      let #(v, i) = do_k(v, True, i)
      let #(t, i) = do_k(t, True, i)
      #(#(a.Let(x, v, t), m), i)
    }
    #(a.Lambda(x, b), m) -> {
      let #(b, i) = do_k(b, True, i)
      #(#(a.Lambda(x, b), m), i)
    }
    #(a.Apply(f, a), m) -> {
      let #(f, i) = do_k(f, False, i)
      let #(a, i) = do_k(a, False, i)
      let call = #(a.Apply(f, a), m)
      case m {
        _ if safe == True -> #(call, i)
        t.Empty -> #(call, i)
        _ -> {
          let var = string.append("$k", int.to_string(i))
          #(#(a.Let(var, call, #(a.Variable(var), t.Empty)), t.Empty), i + 1)
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
//     #(a.Apply(f, a), t.Empty) -> todo
//     #(a.Apply(f, a), m) -> {
//       let #(f, k) = effect_normal(f, k)
//       let #(a, k) = effect_normal(a, k)
//       //   case k {
//       //     // [Value,.] ->
//       //     // [Then]
//       //   }
//       todo
//     }
//     #(a.Lambda(x, b), m) -> {
//       let b = effect_normal(node, fn(x) { x })
//       #(a.Lambda(x, b), m)
//     }
//   }
//   todo
// }
