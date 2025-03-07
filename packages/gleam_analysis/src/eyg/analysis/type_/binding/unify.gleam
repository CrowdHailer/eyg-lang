import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import gleam/dict
import gleam/int
import gleam/io
import gleam/result.{try}

pub fn unify(t1, t2, level, bindings) {
  case do_unify([#(t1, t2)], level, bindings) {
    Error(error.TypeMismatch(t.Var(_x), t.Var(_y))) ->
      Error(error.TypeMismatch(
        binding.resolve(t1, bindings),
        binding.resolve(t2, bindings),
      ))
    result -> result
  }
}

// https://github.com/7sharp9/write-you-an-inference-in-fsharp/blob/master/HMPure-Rowpolymorphism/HMPureRowpolymorphism.fs
// doesn't implement the side condition mentioned in section 7 of https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/scopedlabels.pdf

// Note need to not use `use` for tail recursive functions. https://discord.com/channels/768594524158427167/1256908009389424814
// I have migrated do_unify but not occurs check or rewrite rows/effects

fn do_unify(ts, level, bindings) -> Result(dict.Dict(Int, binding.Binding), _) {
  case ts {
    [] -> Ok(bindings)
    [#(t1, t2), ..ts] -> {
      case t1, find(t1, bindings), t2, find(t2, bindings) {
        t.Var(i), _, t.Var(j), _ if i == j -> do_unify(ts, level, bindings)
        _, Ok(binding.Bound(t1)), _, _ ->
          do_unify([#(t1, t2), ..ts], level, bindings)
        _, _, _, Ok(binding.Bound(t2)) ->
          do_unify([#(t1, t2), ..ts], level, bindings)
        t.Var(i), Ok(binding.Unbound(level)), other, _
        | other, _, t.Var(i), Ok(binding.Unbound(level))
        -> {
          case do_occurs_and_levels(i, level, [other], bindings) {
            Ok(bindings) -> {
              let bindings = dict.insert(bindings, i, binding.Bound(other))
              do_unify(ts, level, bindings)
            }
            Error(reason) -> Error(reason)
          }
        }
        t.Fun(arg1, eff1, ret1), _, t.Fun(arg2, eff2, ret2), _ -> {
          let ts = [#(arg1, arg2), #(eff1, eff2), #(ret1, ret2), ..ts]
          do_unify(ts, level, bindings)
        }
        t.Integer, _, t.Integer, _ -> do_unify(ts, level, bindings)
        t.Binary, _, t.Binary, _ -> do_unify(ts, level, bindings)
        t.String, _, t.String, _ -> do_unify(ts, level, bindings)

        t.List(el1), _, t.List(el2), _ ->
          do_unify([#(el1, el2), ..ts], level, bindings)
        t.Empty, _, t.Empty, _ -> do_unify(ts, level, bindings)
        t.Record(rows1), _, t.Record(rows2), _ ->
          do_unify([#(rows1, rows2), ..ts], level, bindings)
        t.Union(rows1), _, t.Union(rows2), _ ->
          do_unify([#(rows1, rows2), ..ts], level, bindings)
        t.RowExtend(l1, field1, rest1), _, other, _
        | other, _, t.RowExtend(l1, field1, rest1), _
        -> {
          // io.debug(t1)
          // io.debug(t2)
          case rewrite_row(l1, other, level, bindings, rest1) {
            Ok(#(field2, rest2, bindings)) -> {
              let ts = [#(field1, field2), #(rest1, rest2), ..ts]
              do_unify(ts, level, bindings)
            }
            Error(reason) -> Error(reason)
          }
        }
        t.EffectExtend(l1, #(lift1, reply1), r1), _, other, _
        | other, _, t.EffectExtend(l1, #(lift1, reply1), r1), _
        -> {
          case rewrite_effect(l1, other, level, bindings, r1) {
            Ok(#(#(lift2, reply2), r2, bindings)) -> {
              let ts = [#(lift1, lift2), #(reply1, reply2), #(r1, r2), ..ts]
              do_unify(ts, level, bindings)
            }
            Error(reason) -> Error(reason)
          }
        }
        t.Promise(t1), _, t.Promise(t2), _ ->
          do_unify([#(t1, t2), ..ts], level, bindings)
        _, _, _, _ -> Error(error.TypeMismatch(t1, t2))
      }
    }
  }
}

fn find(type_, bindings) {
  case type_ {
    t.Var(i) -> dict.get(bindings, i)
    _other -> Error(Nil)
  }
}

fn do_occurs_and_levels(i, level, types, bindings) {
  case types {
    [] -> Ok(bindings)
    [type_, ..types] ->
      case type_ {
        t.Var(j) if i == j -> Error(error.Recursive)
        t.Var(j) -> {
          let assert Ok(binding) = dict.get(bindings, j)
          case binding {
            binding.Unbound(l) -> {
              let l = int.min(l, level)
              let bindings = dict.insert(bindings, j, binding.Unbound(l))
              do_occurs_and_levels(i, level, types, bindings)
            }
            binding.Bound(type_) ->
              do_occurs_and_levels(i, level, [type_, ..types], bindings)
          }
        }
        t.Fun(arg, eff, ret) -> {
          let types = [arg, eff, ret, ..types]
          do_occurs_and_levels(i, level, types, bindings)
        }
        t.Integer -> do_occurs_and_levels(i, level, types, bindings)
        t.Binary -> do_occurs_and_levels(i, level, types, bindings)
        t.String -> do_occurs_and_levels(i, level, types, bindings)
        t.List(el) -> do_occurs_and_levels(i, level, [el, ..types], bindings)
        t.Record(row) ->
          do_occurs_and_levels(i, level, [row, ..types], bindings)
        t.Union(row) -> do_occurs_and_levels(i, level, [row, ..types], bindings)
        t.Empty -> do_occurs_and_levels(i, level, types, bindings)
        t.RowExtend(_, field, rest) -> {
          let types = [field, rest, ..types]
          do_occurs_and_levels(i, level, types, bindings)
        }
        t.EffectExtend(_, #(lift, reply), rest) -> {
          let types = [lift, reply, rest, ..types]
          do_occurs_and_levels(i, level, types, bindings)
        }
        t.Promise(inner) ->
          do_occurs_and_levels(i, level, [inner, ..types], bindings)
      }
  }
}

fn rewrite_row(required, type_, level, bindings, check) {
  case type_ {
    t.Empty -> Error(error.MissingRow(required))
    t.RowExtend(l, field, rest) if l == required -> Ok(#(field, rest, bindings))
    t.RowExtend(l, other_field, rest) -> {
      use #(field, new_tail, bindings) <- try(rewrite_row(
        required,
        rest,
        level,
        bindings,
        check,
      ))
      let rest = t.RowExtend(l, other_field, new_tail)
      Ok(#(field, rest, bindings))
    }
    t.Var(i) -> {
      case dict.get(bindings, i) {
        Ok(binding.Bound(type_)) ->
          rewrite_row(required, type_, level, bindings, check)
        _ ->
          case check {
            // catch infinite loop
            t.Var(j) if i == j -> {
              io.debug("same tails")
              Error(error.SameTail(t.Var(i), t.Var(j)))
            }
            _ -> {
              // Not sure why this is different to effects
              let #(field, bindings) = binding.mono(level, bindings)
              let #(rest, bindings) = binding.mono(level, bindings)

              let type_ = t.RowExtend(required, field, rest)
              Ok(#(field, rest, dict.insert(bindings, i, binding.Bound(type_))))
            }
          }
      }
    }
    _ -> panic as "bad row"
  }
}

fn rewrite_effect(required, type_, level, bindings, check: t.Type(_)) {
  case type_ {
    t.Empty -> Error(error.MissingRow(required))
    t.EffectExtend(l, eff, rest) if l == required -> Ok(#(eff, rest, bindings))
    t.EffectExtend(l, other_eff, rest) -> {
      use #(eff, new_tail, bindings) <- try(rewrite_effect(
        required,
        rest,
        level,
        bindings,
        check,
      ))
      let rest = t.EffectExtend(l, other_eff, new_tail)
      Ok(#(eff, rest, bindings))
    }
    t.Var(i) ->
      case dict.get(bindings, i) {
        Ok(binding.Bound(type_)) ->
          rewrite_effect(required, type_, level, bindings, check)
        _ -> {
          case check {
            // catch infinite loop
            t.Var(j) if i == j -> {
              io.debug("same effect tails")
              Error(error.TypeMismatch(t.Var(i), t.Var(j)))
            }
            _ -> {
              let #(lift, bindings) = binding.mono(level, bindings)
              let #(reply, bindings) = binding.mono(level, bindings)

              // Might get bound during tail rewrite
              let assert Ok(binding) = dict.get(bindings, i)
              case binding {
                binding.Unbound(level) -> {
                  let #(rest, bindings) = binding.mono(level, bindings)

                  let type_ = t.EffectExtend(required, #(lift, reply), rest)
                  let bindings = dict.insert(bindings, i, binding.Bound(type_))
                  Ok(#(#(lift, reply), rest, bindings))
                }
                binding.Bound(type_) ->
                  rewrite_effect(required, type_, level, bindings, check)
              }
            }
          }
        }
      }
    // _ -> Error(error.TypeMismatch(EffectExtend(required, type_, t.Empty), type_))
    _ -> panic as "bad effect"
  }
}
