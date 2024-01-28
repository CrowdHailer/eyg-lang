import gleam/option.{None}
import gleam/dict
import scintilla/value as v

pub fn scope() {
  // todo module for prelude namespacing
  dict.from_list([
    #("Nil", v.nil),
    #("True", v.true),
    #("False", v.false),
    #("Ok", v.Constructor("Ok", [None])),
    #("Error", v.Constructor("Error", [None])),
  ])
}
