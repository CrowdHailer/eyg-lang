import gleam/set
import gleam/setx

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

pub const unit = Record(Closed)

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
