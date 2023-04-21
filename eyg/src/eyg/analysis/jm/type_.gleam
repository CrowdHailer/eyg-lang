import gleam/map
import gleam/result
import gleam/set
import gleam/setx

pub type Type {
  Var(Int)
  Fun(Type, Type, Type)
  Integer
  String
  LinkedList(Type)
  // Types Record/Union must be Empty/Extend/Var
  Record(Type)
  Union(Type)
  Empty
  RowExtend(String, Type, Type)
  EffectExtend(String, #(Type, Type), Type)
}

pub type Reason {
  Missing
}

pub fn ftv(type_) {
  case type_ {
    Var(a) -> setx.singleton(a)
    Fun(from, effects, to) ->
      set.union(set.union(ftv(from), ftv(effects)), ftv(to))
    Integer | String -> set.new()
    LinkedList(element) -> ftv(element)
    Record(row) -> ftv(row)
    Union(row) -> ftv(row)
    Empty -> set.new()
    RowExtend(_label, value, rest) -> set.union(ftv(value), ftv(rest))
    EffectExtend(_label, #(lift, reply), rest) -> set.union(set.union(ftv(lift), ftv(reply)), ftv(rest))
  }
}

pub fn apply(s, type_) {
  case type_ {
    Var(a) -> result.unwrap(map.get(s, a), type_)
    Fun(from, effects, to) ->
      Fun(apply(s, from), apply(s, effects), apply(s, to))
    Integer | String -> type_
    LinkedList(element) -> LinkedList(apply(s, element))
    Record(row) -> Record(apply(s, row))
    Union(row) -> Union(apply(s, row))
    Empty -> type_
    RowExtend(label, value, rest) -> RowExtend(label, apply(s, value), apply(s, rest))
    EffectExtend(label, #(lift, reply), rest) -> EffectExtend(label, #(apply(s, lift), apply(s, reply)), apply(s, rest))

  }
}

pub fn resolve(t, s) {
  case t {
    // Var(a) ->
    //   map.get(s, a)
    //   |> result.unwrap(t)
    Var(a) -> case map.get(s, a) {
      // recursive resolve needed for non direct unification
      Ok(u) -> resolve(u, s)
      Error(Nil) -> t
    }
    Fun(u, v, w) -> Fun(resolve(u, s), resolve(v, s), resolve(w, s))
    String | Integer | Empty -> t
    LinkedList(element) -> LinkedList(resolve(element, s))
    Record(u) -> Record(resolve(u, s))
    Union(u) -> Union(resolve(u, s))
    RowExtend(label, u, v) ->  RowExtend(label, resolve(u, s), resolve(v, s))
    EffectExtend(label, #(u, v), w) -> EffectExtend(label, #(resolve(u, s), resolve(v, s)), resolve(w, s))
  }
}

pub fn fresh(next)  {
  #(Var(next), next + 1)
}

pub fn tail(next)  {
  let #(item, next) = fresh(next)
  #(LinkedList(item), next)
}

pub fn cons(next) {
  let #(item, next) = fresh(next)
  let #(e1, next) = fresh(next)
  let #(e2, next) = fresh(next)
  let t = Fun(item, e1, Fun(LinkedList(item), e2, LinkedList(item)))
  #(t, next)
}

pub fn empty(next) {
  #(Record(Empty), next)
}

pub fn extend(label, next) {
  let #(value, next) = fresh(next)
  let #(rest, next) = fresh(next)
  let #(e1, next) = fresh(next)
  let #(e2, next) = fresh(next)
  let t = Fun(value, e1, Fun(Record(rest), e2, Record(RowExtend(label, value, rest))))
  #(t, next)
}

pub fn select(label, next) {
  let #(value, next) = fresh(next)
  let #(rest, next) = fresh(next)
  let #(e, next) = fresh(next)
  let t = Fun(Record(RowExtend(label, value, rest)), e, value)
  #(t, next)
}

pub fn overwrite(label, next) {
  let #(new, next) = fresh(next)
  let #(old, next) = fresh(next)
  let #(rest, next) = fresh(next)
  let #(e1, next) = fresh(next)
  let #(e2, next) = fresh(next)
  let t = Fun(new, e1, Fun(Record(RowExtend(label, old, rest)), e2, Record(RowExtend(label, new, rest))))
  #(t, next)
}

pub fn tag(label, next) {
  let #(value, next) = fresh(next)
  let #(rest, next) = fresh(next)
  let #(e, next) = fresh(next)
  let t = Fun(value, e, Union(RowExtend(label, value, rest)))
  #(t, next)
}

pub fn case_(label, next) {
  let #(value, next) = fresh(next)
  let #(ret, next) = fresh(next)
  let #(rest, next) = fresh(next)
  let #(e1, next) = fresh(next)
  let #(e2, next) = fresh(next)
  let #(e3, next) = fresh(next)
  let #(e4, next) = fresh(next)
  let #(e5, next) = fresh(next)
  let branch = Fun(value, e1, ret)
  let else = Fun(Union(rest), e2, ret)
  let exec = Fun(Union(RowExtend(label, value, rest)), e3, ret)
  let t = Fun(branch, e4, Fun(else, e5, exec))
  #(t, next)
}

pub fn nocases(next) {
  let #(ret, next) = fresh(next)
  let #(e, next) = fresh(next)
  let t = Fun(Union(Empty), e, ret)
  #(t, next)
}

pub fn perform(label, next) {
  let #(arg, next) = fresh(next)
  let #(ret, next) = fresh(next)
  let #(tail, next) = fresh(next)
  let t = Fun(arg, EffectExtend(label, #(arg, ret), tail), ret)
  #(t, next)
}

pub fn handle(label, next) {
  let #(ret, next) = fresh(next)
  let #(lift, next) = fresh(next)
  let #(reply, next) = fresh(next)
  let #(tail, next) = fresh(next)
  let #(e, next) = fresh(next)

  let kont = Fun(reply, tail, ret)
  let handler = Fun(lift, tail, Fun(kont, tail, ret))
  let exec = Fun(unit, EffectExtend(label, #(lift, reply), tail), ret)
  let t = Fun(handler, e, Fun(exec, tail, ret))
  #(t, next)
}

pub const unit = Record(Empty)

pub const boolean = Union(RowExtend("True", unit, RowExtend("False", unit, Empty)))