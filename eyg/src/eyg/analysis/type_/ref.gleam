import gleam/list
import gleam/javascript as js
import eyg/analysis/type_/isomorphic as t

pub type Binding {
  Bound(Mono)
  Unbound(level: Int)
}

pub type Mono =
  t.Type(js.Reference(Binding))

pub type Quantified {
  Quantified(Int)
  Unquantified(js.Reference(Binding))
}

// Keep poly as separate type, don't just make Quantified a binding option
// to do so would loose a bunch of type safety at which point zig/wasm is an obvious choise
// Maybe it was always an obvious choice if the problem is this thoroughly understood/fundamentally about the algorithm.

pub type Poly =
  t.Type(Quantified)

// TODO stye guide For single lines what about let g = gen(_, level)
// Call it bike shed. ScooterTent
fn gen(type_, level) {
  case type_ {
    t.Var(ref) ->
      case js.dereference(ref) {
        Bound(type_) -> gen(type_, level)
        // could just keep using ref, this might be a good place to put all instantiations for monomorpisatio
        Unbound(l) if l > level -> t.Var(Quantified(0))
        // Set Binding to Quantified then add to list
        Unbound(_) -> t.Var(Unquantified(ref))
      }
    t.Fun(arg, eff, ret) -> {
      let arg = gen(arg, level)
      let eff = gen(eff, level)
      let ret = gen(ret, level)
      t.Fun(arg, eff, ret)
    }
    t.Integer -> t.Integer
    t.Binary -> t.Binary
    t.String -> t.String
    t.List(el) -> t.List(gen(el, level))
    t.Record(rows) -> t.Record(gen(rows, level))
    t.Union(rows) -> t.Union(gen(rows, level))
    t.Empty -> t.Empty
    t.RowExtend(label, field, rest) -> {
      let field = gen(field, level)
      let rest = gen(rest, level)
      t.RowExtend(label, field, rest)
    }
    t.EffectExtend(label, #(lift, reply), rest) -> {
      let lift = gen(lift, level)
      let reply = gen(reply, level)
      let rest = gen(rest, level)
      t.EffectExtend(label, #(lift, reply), rest)
    }
  }
}

// is there a neat way to tail cal optimise this Gleam style
pub fn inst(poly, level) {
  case poly {
    t.Var(Quantified(ref)) -> {
      let found =
        list.find_map([], fn(sub) {
          let #(original, replace) = sub
          // let ref_equal(origial, ref)
          Ok(replace)
        })
      case found {
        Ok(mono) -> mono
        Error(Nil) -> {
          let replace = t.Var(js.make_reference(Unbound(level)))
          // Put original in subs
        }
      }
      todo
      // #(mono)
    }
    t.Var(Unquantified(ref)) -> #(t.Var(ref))
    t.List(el) -> {
      let #(el) = inst(el, level)
      #(t.List(el))
    }
    _ -> todo
  }
}

// How to unnest the unification function
// Start a something called gleam style
fn unify(t1, t2) {
  // TODO ref equality, can't be done on type because the function would need to take ref from inside var
  // js.re
  case t1, t2 {
    t.Var(ref1), t2 ->
      case js.dereference(ref1) {
        Bound(t1) -> unify(t1, t2)
        Unbound(level) -> bind(level, ref1, t2)
      }
    t1, t.Var(ref2) ->
      case js.dereference(ref2) {
        Bound(t2) -> unify(t1, t2)
        Unbound(level) -> bind(level, ref2, t1)
      }
    _, _ -> todo
  }
}

fn bind(level, ref, type_) {
  // todo occurs
  js.set_reference(ref, Bound(type_))
  Ok(Nil)
}
