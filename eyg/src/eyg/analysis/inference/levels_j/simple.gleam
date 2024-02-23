import gleam/dict
import gleam/javascript as js
import eygir/expression as e
import eyg/analysis/type_/ref
import eyg/analysis/type_/isomorphic as t

// have a poly/mono file to import then m.binary or p.unquantified(level)

fn new_poly(level) {
  t.Var(#(False, js.make_reference(ref.Unbound(level))))
}

fn new_mono(level) {
  t.Var(js.make_reference(ref.Unbound(level)))
}

// TODO can you reexport constructors
pub fn j(exp, env, level) {
  case exp {
    e.Variable(x) -> {
      let assert Ok(poly) = dict.get(env, x)
      ref.inst(poly, level)
    }
    e.Apply(func, arg) -> {
      let ret = new_mono(level)
      let f = j(func, env, level)
      let a = j(arg, env, level)
      let assert Ok(Nil) = ref.unify(t.Fun(a, t.Empty, ret), f)
      ret
    }
    e.Lambda(x, body) -> {
      let env = dict.insert(env, x, new_poly(level))
      j(body, env, level)
    }
    e.Let(x, value, then) -> {
      let v = j(value, env, level + 1)
      let env = dict.insert(env, x, ref.gen(v, level))
      //   let env = [#(x, ref.gen(v, level)), ..env]
      j(then, env, level)
    }
    _ -> {
      todo
      // let new = t.newvar(level)
      // let in = t.Record(t.RowExtend(x, t.newvar(level), rest))
      // let out = t.Record(t.RowExtend(x, new, rest))
      // t.Fun(new, t.Fun(in, out))
    }
  }
}
