import language/scope
import language/ast/builder.{constructor, varient}
import language/type_.{Variable}

pub fn with_boolean(in) {
  varient(
    "Boolean",
    [],
    [constructor("True", []), constructor("False", [])],
    in,
  )
}

pub fn with_option(in) {
  varient(
    "Option",
    [1],
    [constructor("Some", [Variable(1)]), constructor("None", [])],
    in,
  )
}
