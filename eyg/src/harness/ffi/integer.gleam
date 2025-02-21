import eyg/analysis/typ as t
import eyg/interpreter/builtin

pub fn compare() {
  let type_ =
    t.Fun(
      t.Integer,
      t.Open(0),
      t.Fun(
        t.Integer,
        t.Open(1),
        t.Union(t.Extend(
          "Lt",
          t.unit,
          t.Extend("Eq", t.unit, t.Extend("Gt", t.unit, t.Closed)),
        )),
      ),
    )
  #(type_, builtin.int_compare)
}

pub fn add() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, builtin.add)
}

pub fn subtract() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, builtin.subtract)
}

pub fn multiply() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, builtin.multiply)
}

pub fn divide() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, builtin.divide)
}

pub fn absolute() {
  let type_ = t.Fun(t.Integer, t.Open(0), t.Integer)
  #(type_, builtin.absolute)
}

pub fn parse() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Integer)
  #(type_, builtin.int_parse)
}

pub fn to_string() {
  let type_ = t.Fun(t.Integer, t.Open(0), t.Str)
  #(type_, builtin.int_to_string)
}
