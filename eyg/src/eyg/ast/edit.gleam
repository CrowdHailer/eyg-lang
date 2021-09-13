import gleam/io
import gleam/option.{Option, Some, None}
import eyg/ast
import eyg/ast/expression.{Expression}

pub type Path = List(Int)
    

pub type Action {
    WrapTuple
}

pub type Edit {
    Edit(Action, Path)
}

pub fn edit(action, path) {
    Edit(action, path)
}

pub fn apply_edit(tree, edit) -> #(Expression(Nil), Path) {
    let Edit(action, path) = edit
    case action {
        WrapTuple -> wrap_tuple(tree, path)
    }
}

fn wrap_tuple(tree, path) {
    case path {
        [] -> #(ast.tuple_([tree]), ast.append_path(path, 0))
    }
}

pub fn shotcut_for_binary(string, control_pressed) -> Option(Action) {
    case string, control_pressed {
        "[", True -> Some(WrapTuple)
        _, _ -> None 
    }
}