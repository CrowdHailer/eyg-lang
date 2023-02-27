import gleam/int
import gleam/list
import gleam/set
import gleam/string
import eyg/analysis/typ as t
import eyg/analysis/unification
import eyg/analysis/substitutions as sub

// Do we have a general need for type debug functionality
pub fn render(type_info) {
  case type_info {
    Ok(t) -> render_type(shrink(t))
    Error(f) -> render_failure(f)
  }
}

pub fn render_failure(f) {
  case f {
    unification.TypeMismatch(a, b) ->
      // need to shrink errors together
      string.concat(["Type Missmatch: ", render_type(a), " vs ", render_type(b)])
    unification.RowMismatch(label) -> string.append("Row Missmatch: ", label)
    unification.MissingVariable(x) -> string.append("missing variable: ", x)
    unification.RecursiveType -> "Recursive type"
  }
}

pub fn render_type(typ) {
  case typ {
    t.Unbound(i) -> int.to_string(i)
    t.Integer -> "Integer"
    t.Binary -> "Binary"
    t.LinkedList(el) -> string.concat(["List(", render_type(el), ")"])
    t.Fun(from, effects, to) ->
      string.concat([
        "(",
        render_type(from),
        ") ->",
        render_effects(effects),
        " ",
        render_type(to),
      ])
    t.Union(row) ->
      string.concat([
        "[",
        string.concat(
          render_row(row)
          |> list.intersperse(" | "),
        ),
        "]",
      ])
    t.Record(row) ->
      string.concat([
        "{",
        string.concat(
          render_row(row)
          |> list.intersperse(", "),
        ),
        "}",
      ])
  }
}

fn render_row(r) -> List(String) {
  case r {
    t.Closed -> []
    t.Open(i) -> [string.append("..", int.to_string(i))]
    t.Extend(label, value, tail) -> {
      let field = string.concat([label, ": ", render_type(value)])
      [field, ..render_row(tail)]
    }
  }
}

fn render_effects(effects) {
  case effects {
    t.Open(_) | t.Closed -> ""
    t.Extend(label, #(lift, resume), tail) ->
      string.concat([
        " <",
        string.join(
          collect_effect(tail, [render_effect(label, lift, resume)]),
          ", ",
        ),
        ">",
      ])
  }
}

fn render_effect(label, lift, resume) {
  string.concat([label, "(", render_type(lift), ", ", render_type(resume), ")"])
}

fn collect_effect(eff, acc) {
  case eff {
    t.Extend(label, #(lift, resume), tail) ->
      collect_effect(tail, [render_effect(label, lift, resume), ..acc])
    _ -> acc
  }
}

// Shrink not needed in analysis

fn do_used_in_type(used, type_) {
  case type_ {
    t.Unbound(i) -> set.insert(used, i)
    t.Integer | t.Binary -> used
    t.LinkedList(el) -> do_used_in_type(used, el)
    t.Fun(arg, effect, ret) ->
      used
      |> do_used_in_type(arg)
      |> do_used_in_effect(effect)
      |> do_used_in_type(ret)
    t.Record(row) | t.Union(row) -> do_used_in_row(used, row)
  }
}

fn do_used_in_row(used, row) {
  case row {
    t.Open(i) -> set.insert(used, i)
    t.Closed -> used
    t.Extend(_, value, tail) ->
      used
      |> do_used_in_type(value)
      |> do_used_in_row(tail)
  }
}

fn do_used_in_effect(used, eff) -> set.Set(Int) {
  case eff {
    t.Open(i) -> set.insert(used, i)
    t.Closed -> used
    t.Extend(_, #(lift, reply), tail) -> {
      let x =
        used
        |> do_used_in_type(lift)
        |> do_used_in_type(reply)

      do_used_in_effect(x, tail)
    }
  }
}

pub fn used_in_type(t) {
  do_used_in_type(set.new(), t)
}

pub fn shrink(type_) {
  shrink_to(type_, 0)
}

pub fn shrink_to(type_, _i) {
  let used = used_in_type(type_)
  used
  |> set.to_list
  |> list.index_fold(
    sub.none(),
    fn(s, used, i) {
      // Simple implementation is to add a translation for every kind
      s
      |> sub.insert_term(used, t.Unbound(i))
      |> sub.insert_row(used, t.Open(i))
      |> sub.insert_effect(used, t.Open(i))
    },
  )
  |> sub.apply(type_)
}
