import gleam/dict.{type Dict}
import gleam/option.{type Option}
import glance
import scintilla/value.{type Value}

pub type Reason {
  NotAFunction(Value)
  IncorrectArity(expected: Int, given: Int)
  UndefinedVariable(String)
  Panic(message: Option(String))
  Todo(message: Option(String))
  OutOfRange(size: Int, given: Int)
  NoMatch(values: List(Value))
  IncorrectTerm(expected: String, got: Value)
  FailedAssignment(pattern: glance.Pattern, value: Value)
  MissingField(String)
  Finished(Dict(String, Value))
  UnknownModule(String)
}
