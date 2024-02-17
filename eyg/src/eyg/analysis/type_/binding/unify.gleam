import gleam/dict.{type Dict}
import gleam/io
import gleam/int
import gleam/list
import gleam/result.{try}
import gleam/set
import eygir/expression as e
import eyg/analysis/type_/isomorphic as t
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error

pub fn unify(t1, t2, level, bindings) {
  case t1, find(t1, bindings), t2, find(t2, bindings) {
    _, Ok(binding.Bound(t1)), _, _ -> unify(t1, t2, level, bindings)
    _, _, _, Ok(binding.Bound(t2)) -> unify(t1, t2, level, bindings)
    t.Var(i), _, t.Var(j), _ if i == j -> Ok(bindings)
    t.Var(i), Ok(binding.Unbound(level)), other, _
    | other, _, t.Var(i), Ok(binding.Unbound(level)) -> {
      use bindings <- try(occurs_and_levels(i, level, other, bindings))
      Ok(dict.insert(bindings, i, binding.Bound(other)))
    }
    t.Fun(arg1, eff1, ret1), _, t.Fun(arg2, eff2, ret2), _ -> {
      use bindings <- try(unify(arg1, arg2, level, bindings))
      use bindings <- try(unify(eff1, eff2, level, bindings))
      unify(ret1, ret2, level, bindings)
    }
    t.Integer, _, t.Integer, _ -> Ok(bindings)
    t.Binary, _, t.Binary, _ -> Ok(bindings)
    t.String, _, t.String, _ -> Ok(bindings)

    t.List(el1), _, t.List(el2), _ -> unify(el1, el2, level, bindings)
    t.Empty, _, t.Empty, _ -> Ok(bindings)
    t.Record(rows1), _, t.Record(rows2), _ ->
      unify(rows1, rows2, level, bindings)
    t.Union(rows1), _, t.Union(rows2), _ -> unify(rows1, rows2, level, bindings)
    t.RowExtend(l1, field1, rest1), _, other, _
    | other, _, t.RowExtend(l1, field1, rest1), _ -> {
      use #(field2, rest2, bindings) <- try(rewrite_row(
        l1,
        other,
        level,
        bindings,
      ))
      use bindings <- try(unify(field1, field2, level, bindings))
      unify(rest1, rest2, level, bindings)
    }
    t.EffectExtend(l1, #(lift1, reply1), r1), _, other, _
    | other, _, t.EffectExtend(l1, #(lift1, reply1), r1), _ -> {
      use #(#(lift2, reply2), r2, bindings) <- try(rewrite_effect(
        l1,
        other,
        level,
        bindings,
      ))
      use bindings <- try(unify(lift1, lift2, level, bindings))
      use bindings <- try(unify(reply1, reply2, level, bindings))
      unify(r1, r2, level, bindings)
    }
    _, _, _, _ -> Error(error.TypeMismatch(t1, t2))
  }
}

fn find(type_, bindings) {
  case type_ {
    t.Var(i) -> dict.get(bindings, i)
    _other -> Error(Nil)
  }
}

fn occurs_and_levels(i, level, type_, bindings) {
  case type_ {
    t.Var(j) if i == j -> Error(error.Recursive)
    t.Var(j) -> {
      let assert Ok(binding) = dict.get(bindings, j)
      case binding {
        binding.Unbound(l) -> {
          let l = int.min(l, level)
          let bindings = dict.insert(bindings, j, binding.Unbound(l))
          Ok(bindings)
        }
        binding.Bound(type_) -> occurs_and_levels(i, level, type_, bindings)
      }
    }
    t.Fun(arg, eff, ret) -> {
      use bindings <- try(occurs_and_levels(i, level, arg, bindings))
      use bindings <- try(occurs_and_levels(i, level, eff, bindings))
      use bindings <- try(occurs_and_levels(i, level, ret, bindings))
      Ok(bindings)
    }
    t.Integer -> Ok(bindings)
    t.Binary -> Ok(bindings)
    t.String -> Ok(bindings)
    t.List(el) -> occurs_and_levels(i, level, el, bindings)
    t.Record(row) -> occurs_and_levels(i, level, row, bindings)
    t.Union(row) -> occurs_and_levels(i, level, row, bindings)
    t.Empty -> Ok(bindings)
    t.RowExtend(_, field, rest) -> {
      use bindings <- try(occurs_and_levels(i, level, field, bindings))
      use bindings <- try(occurs_and_levels(i, level, rest, bindings))
      Ok(bindings)
    }
    t.EffectExtend(_, #(lift, reply), rest) -> {
      use bindings <- try(occurs_and_levels(i, level, lift, bindings))
      use bindings <- try(occurs_and_levels(i, level, reply, bindings))
      use bindings <- try(occurs_and_levels(i, level, rest, bindings))
      Ok(bindings)
    }
  }
}

fn rewrite_row(required, type_, level, bindings) {
  case type_ {
    t.Empty -> Error(error.MissingRow(required))
    t.RowExtend(l, field, rest) if l == required -> Ok(#(field, rest, bindings))
    t.RowExtend(l, other_field, rest) -> {
      use #(field, new_tail, bindings) <- try(rewrite_row(
        l,
        rest,
        level,
        bindings,
      ))
      let rest = t.RowExtend(required, other_field, new_tail)
      Ok(#(field, rest, bindings))
    }
    t.Var(i) -> {
      let #(field, bindings) = binding.mono(level, bindings)
      let #(rest, bindings) = binding.mono(level, bindings)
      let type_ = t.RowExtend(required, field, rest)
      Ok(#(field, rest, dict.insert(bindings, i, binding.Bound(type_))))
    }
    // _ -> Error(error.TypeMismatch(t.RowExtend(required, type_, t.Empty), type_))
    _ -> panic as "bad row"
  }
}

fn rewrite_effect(required, type_, level, bindings) {
  case type_ {
    t.Empty -> Error(error.MissingRow(required))
    t.EffectExtend(l, eff, rest) if l == required -> Ok(#(eff, rest, bindings))
    t.EffectExtend(l, other_eff, rest) -> {
      use #(eff, new_tail, bindings) <- try(rewrite_effect(
        required,
        rest,
        level,
        bindings,
      ))
      // use #(eff, new_tail, s) <-  try(rewrite_effect(l, rest, s))
      let rest = t.EffectExtend(l, other_eff, new_tail)
      Ok(#(eff, rest, bindings))
    }
    t.Var(i) -> {
      let #(lift, bindings) = binding.mono(level, bindings)
      let #(reply, bindings) = binding.mono(level, bindings)

      case dict.get(bindings, i) {
        Ok(binding.Unbound(level)) -> {
          let #(rest, bindings) = binding.mono(level, bindings)

          let type_ = t.EffectExtend(required, #(lift, reply), rest)
          Ok(#(
            #(lift, reply),
            rest,
            dict.insert(bindings, i, binding.Bound(type_)),
          ))
        }
        // Might get bound during tail rewrite
        Ok(binding.Bound(type_)) ->
          rewrite_effect(required, type_, level, bindings)
      }
    }
    // _ -> Error(error.TypeMismatch(EffectExtend(required, type_, t.Empty), type_))
    _ -> panic as "bad effect"
  }
}
