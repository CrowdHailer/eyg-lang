import eygir/expression as e

pub fn binary(value) {
  e.Apply(e.Tag("Binary"), e.Binary(value))
}

pub fn integer(value) {
  e.Apply(e.Tag("Integer"), e.Integer(value))
}

pub fn variable(label) {
  e.Apply(e.Tag("Variable"), e.Binary(label))
}

// TODO decide func fun lambda, use constants for keys
pub fn lambda(param, body) {
  e.Apply(
    e.Tag("Lambda"),
    e.Apply(
      e.Apply(e.Extend("label"), e.Binary(param)),
      e.Apply(e.Apply(e.Extend("body"), body), e.Empty),
    ),
  )
}
