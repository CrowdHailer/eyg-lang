import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eyg
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer
import eyg/typer/monotype as t
import eyg/typer/polytype
import misc

pub fn infer(untyped, type_) {
  let native_to_string = fn(_: Nil) { "TODO" }
  let variables = [#("equal", typer.equal_fn())]
  let checker = typer.init(native_to_string)
  let scope = typer.root_scope(variables)
  let state = #(checker, scope)
  typer.infer(untyped, type_, state)
}

fn incrementor(i) {
  #(i, i + 1)
}

pub fn get_type(typed, checker: typer.Typer(n)) {
  case typer.get_type(typed) {
    Ok(type_) -> {
      let type_ = t.resolve(type_, checker.substitutions)
      let type_ = shrink(type_)
      Ok(type_)
    }
    // TODO resolve error
    Error(reason) -> Error(reason)
  }
}

pub fn shrink(type_) {
  let used = t.used_in_type(type_)
  let minimal = misc.zip_with(used, 0, incrementor)
  list.fold(
    minimal,
    type_,
    fn(type_, replace) {
      let #(old, new) = replace
      polytype.replace_variable(type_, old, new)
    },
  )
}

pub fn print(type_, _) {
  t.to_string(type_, fn(_) { "TODO again" })
}
