import gleam/int
import gleam/list
import gleam/javascript as js
import gleam/javascriptx as jsx
import eyg/analysis/type_/isomorphic as t

pub type Binding {
  Bound(Mono)
  Unbound(level: Int)
}

pub type Mono =
  t.Type(js.Reference(Binding))

// pub type Quantified {
//   Quantified(Int)
//   Unquantified(js.Reference(Binding))
// }

// Keep poly as separate type, don't just make Quantified a binding option
// to do so would loose a bunch of type safety at which point zig/wasm is an obvious choise
// Maybe it was always an obvious choice if the problem is this thoroughly understood/fundamentally about the algorithm.

pub type Poly =
  t.Type(#(Bool, js.Reference(Binding)))

// TODO stye guide For single lines what about let g = gen(_, level)
// Call it bike shed. ScooterTent
// Set Binding to Quantified then add to list
// could just keep using ref, this might be a good place to put all instantiations for monomorpisatio
pub fn gen(type_, level) {
  case type_ {
    t.Var(ref) ->
      case js.dereference(ref) {
        Bound(type_) -> gen(type_, level)
        Unbound(l) if l > level -> t.Var(#(True, ref))
        Unbound(_) -> t.Var(#(False, ref))
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

pub fn inst(poly, level) {
  let #(mono, _) = do_inst(poly, level, [])
  mono
}

// is there a neat way to tail cal optimise this Gleam style

fn do_inst(poly, level, subs) {
  case poly {
    t.Var(#(True, ref)) -> {
      let found =
        list.find_map(subs, fn(sub) {
          let #(original, replace) = sub
          case jsx.reference_equal(original, ref) {
            True -> Ok(replace)
            False -> Error(Nil)
          }
        })
      case found {
        Ok(mono) -> #(mono, subs)
        Error(Nil) -> {
          let new = t.Var(js.make_reference(Unbound(level)))
          #(new, [#(ref, new), ..subs])
        }
      }
    }
    t.Var(#(False, ref)) -> #(t.Var(ref), subs)
    t.List(el) -> {
      let #(el, subs) = do_inst(el, level, subs)
      #(t.List(el), subs)
    }
    _ -> todo
  }
}

// How to unnest the unification function
// Start a something called gleam style
pub fn unify(t1, t2) {
  case t1, t2 {
    t.Var(ref1), t.Var(ref2) ->
      case jsx.reference_equal(ref1, ref2) {
        True -> Ok(Nil)
        False -> do_unify(t1, t2)
      }
    t1, t2 -> do_unify(t1, t2)
  }
}

fn do_unify(t1, t2) {
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
  occurs_and_levels(ref, level, type_)
  js.set_reference(ref, Bound(type_))
  Ok(Nil)
}

fn occurs_and_levels(ref, level, type_) {
  case type_ {
    t.Var(r) ->
      case jsx.reference_equal(ref, r) {
        True -> panic
        False ->
          case js.dereference(r) {
            Unbound(l) -> {
              js.set_reference(r, Unbound(int.min(l, level)))
              Nil
            }
            Bound(type_) -> occurs_and_levels(ref, level, type_)
          }
      }
    t.Fun(arg, eff, ret) -> {
      occurs_and_levels(ref, level, arg)
      occurs_and_levels(ref, level, eff)
      occurs_and_levels(ref, level, ret)
    }
    t.Integer -> Nil
    t.Binary -> Nil
    t.String -> Nil
    t.List(el) -> occurs_and_levels(ref, level, el)
    t.Record(row) -> occurs_and_levels(ref, level, row)
    t.Union(row) -> occurs_and_levels(ref, level, row)
    t.Empty -> Nil
    t.RowExtend(_, field, rest) -> {
      occurs_and_levels(ref, level, field)
      occurs_and_levels(ref, level, rest)
    }
    t.EffectExtend(_, #(lift, reply), rest) -> {
      occurs_and_levels(ref, level, lift)
      occurs_and_levels(ref, level, reply)
      occurs_and_levels(ref, level, rest)
    }
  }
}
