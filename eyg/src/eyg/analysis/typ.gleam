import gleam/set
import gleam/setx
import gleam/javascript

// This separation of kinds could be opened as a PR to the F-sharp project

pub type Row(kind) {
  Closed
  Open(Int)
  Extend(label: String, value: kind, tail: Row(kind))
}

pub type Term {
  Unbound(Int)
  Integer
  Binary
  LinkedList(Term)
  Fun(Term, Row(#(Term, Term)), Term)
  // Row parameterised by T for effects
  Union(Row(Term))
  Record(Row(Term))
}

pub type Variable {
  Term(Int)
  Row(Int)
  Effect(Int)
}

pub fn ftv(typ) {
  case typ {
    Unbound(x) -> setx.singleton(Term(x))
    Integer | Binary -> set.new()
    LinkedList(element) -> ftv(element)
    Record(row) -> ftv_row(row)
    Union(row) -> ftv_row(row)
    Fun(from, effects, to) ->
      set.union(set.union(ftv(from), ftv_effect(effects)), ftv(to))
  }
}

fn ftv_row(row) {
  case row {
    Closed -> set.new()
    Open(x) -> setx.singleton(Row(x))
    Extend(_label, value, tail) -> set.union(ftv(value), ftv_row(tail))
  }
}

fn ftv_effect(row) {
  case row {
    Closed -> set.new()
    Open(x) -> setx.singleton(Effect(x))
    Extend(_label, #(from, to), tail) ->
      set.union(set.union(ftv(from), ftv(to)), ftv_effect(tail))
  }
}

pub const unit = Record(Closed)

pub const boolean = Union(Extend("True", unit, Extend("False", unit, Closed)))

pub fn result(value, reason) {
  Union(Extend("Ok", value, Extend("Error", reason, Closed)))
}

pub fn option(value) {
  Union(Extend("Some", value, Extend("None", unit, Closed)))
}

pub fn tail(ref) {
  LinkedList(Unbound(fresh(ref)))
}

pub fn cons(ref) {
  let t = Unbound(fresh(ref))
  let e1 = Open(fresh(ref))
  let e2 = Open(fresh(ref))
  Fun(t, e1, Fun(LinkedList(t), e2, LinkedList(t)))
}

pub fn empty() {
  Record(Closed)
}

pub fn extend(label, ref) {
  let t = Unbound(fresh(ref))
  let r = Open(fresh(ref))
  let e1 = Open(fresh(ref))
  let e2 = Open(fresh(ref))
  Fun(t, e1, Fun(Record(r), e2, Record(Extend(label, t, r))))
}

pub fn select(label, ref) {
  let t = Unbound(fresh(ref))
  let r = Open(fresh(ref))
  let e = Open(fresh(ref))
  Fun(Record(Extend(label, t, r)), e, t)
}

pub fn overwrite(label, ref) {
  let t = Unbound(fresh(ref))
  let u = Unbound(fresh(ref))
  let r = Open(fresh(ref))
  let e1 = Open(fresh(ref))
  let e2 = Open(fresh(ref))
  Fun(t, e1, Fun(Record(Extend(label, u, r)), e2, Record(Extend(label, t, r))))
}

pub fn tag(label, ref) {
  let t = Unbound(fresh(ref))
  let r = Open(fresh(ref))
  let e = Open(fresh(ref))
  Fun(t, e, Union(Extend(label, t, r)))
}

pub fn case_(label, ref) {
  let t = Unbound(fresh(ref))
  let ret = Unbound(fresh(ref))
  let r = Open(fresh(ref))
  let e1 = Open(fresh(ref))
  let e2 = Open(fresh(ref))
  let e3 = Open(fresh(ref))
  let e4 = Open(fresh(ref))
  let e5 = Open(fresh(ref))
  let branch = Fun(t, e1, ret)
  let else = Fun(Union(r), e2, ret)
  let exec = Fun(Union(Extend(label, t, r)), e3, ret)
  Fun(branch, e4, Fun(else, e5, exec))
}

pub fn nocases(ref) {
  // unbound return to match cases
  let t = Unbound(fresh(ref))
  let e = Open(fresh(ref))
  Fun(Union(Closed), e, t)
}

pub fn perform(label, ref) {
  let arg = Unbound(fresh(ref))
  let ret = Unbound(fresh(ref))
  let tail = Open(fresh(ref))
  Fun(arg, Extend(label, #(arg, ret), tail), ret)
}

// reused for shallow
pub fn handle(label, ref) {
  let ret = Unbound(fresh(ref))
  let lift = Unbound(fresh(ref))
  let reply = Unbound(fresh(ref))
  let tail = Open(fresh(ref))

  let kont = Fun(reply, tail, ret)
  let handler = Fun(lift, tail, Fun(kont, tail, ret))
  let exec = Fun(unit, Extend(label, #(lift, reply), tail), ret)
  Fun(handler, Open(fresh(ref)), Fun(exec, tail, ret))
}

// copied from unification to not get circular ref
pub fn fresh(ref) {
  javascript.update_reference(ref, fn(x) { x + 1 })
}
