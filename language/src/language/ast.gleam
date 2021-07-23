import option.{None, Option, Some}

// Use opaque type to keep in type information
pub type Expression(t) {
  // Pattern is name in Let
  Let(name: String, value: #(t, Expression(t)), in: #(t, Expression(t)))
  Var(name: String)
  Binary
  Case
  Tuple
  // arguments are names only
  Function(arguments: List(#(t, String)), body: #(t, Expression(t)))
  Call(function: #(t, Expression(t)), arguments: List(#(t, Expression(t))))
}
