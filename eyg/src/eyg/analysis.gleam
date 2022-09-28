import gleam/io
import gleam/list
import eyg
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer
import eyg/typer/monotype as t
import eyg/typer/polytype
import eyg/editor/type_info

pub fn infer(untyped, type_, variables) {
  let checker = typer.init()
  let scope = typer.root_scope(variables)
  let state = #(checker, scope)
  typer.infer(untyped, type_, t.empty, state)
}

pub fn infer_effectful(untyped, type_, effects, variables) {
  let checker = typer.init()
  let scope = typer.root_scope(variables)
  let state = #(checker, scope)
  typer.infer(untyped, type_, effects, state)
}

pub fn get_type(typed, checker: typer.Typer) {
  case typer.get_type(typed) {
    Ok(type_) -> {
      let type_ = t.resolve(type_, checker.substitutions)
      let type_ = polytype.shrink(type_)
      Ok(type_)
    }
    Error(reason) -> {
      let reason = type_info.resolve_reason(reason, checker)
      Error(reason)
    }
  }
}
