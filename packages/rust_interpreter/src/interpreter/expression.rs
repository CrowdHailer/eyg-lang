// execute / call / resume
// Mirrors packages/gleam_interpreter/src/eyg/interpreter/expression.gleam

use super::state::{Control, Env, EvalResult, Next, Stack};
use super::value::{Scope, Value};
use crate::ir::ast::Node;
use im;
use std::rc::Rc;

/// Main evaluation loop
pub fn eval_loop(next: Next) -> EvalResult {
    match next {
        Next::Loop(c, e, k) => eval_loop(super::state::step(c, e, k)),
        Next::Break(result) => result,
    }
}

/// Execute an expression with a given scope
pub fn execute(exp: Node, scope: Scope) -> EvalResult {
    eval_loop(super::state::step(
        Control::Expr(exp),
        new_env(scope),
        Box::new(Stack::Empty(im::HashMap::new())),
    ))
}

/// Call a function with arguments
pub fn call(f: Rc<Value>, args: Vec<(Rc<Value>, ())>) -> EvalResult {
    let env = new_env(im::Vector::new());
    let h = im::HashMap::new();

    // Build the stack with CallWith frames for each argument
    let mut k = Stack::Empty(h);
    for (value, meta) in args.into_iter().rev() {
        k = Stack::Frame(
            super::state::Kontinue::CallWith(value, env.clone()),
            meta,
            Box::new(k),
        );
    }

    eval_loop(super::state::step(Control::Val(f), env, Box::new(k)))
}

/// Resume evaluation with a value
pub fn resume(value: Rc<Value>, env: Env, k: Stack) -> EvalResult {
    eval_loop(super::state::step(Control::Val(value), env, Box::new(k)))
}

/// Create a new environment with the given scope
pub fn new_env(scope: Scope) -> Env {
    Env {
        scope,
        references: im::HashMap::new(),
        builtins: builtins(),
    }
}

/// Build the builtins map
/// Mirrors the builtins() function from packages/gleam_interpreter/src/eyg/interpreter/expression.gleam
fn builtins() -> im::HashMap<String, super::state::Builtin> {
    use super::builtin;
    use super::state::Builtin;

    let mut map = im::HashMap::new();

    // Equality / control flow
    map.insert("equal".to_string(), Builtin::Arity2(builtin::equal));
    map.insert("fix".to_string(), Builtin::Arity1(builtin::fix));
    map.insert("fixed".to_string(), Builtin::Arity2(builtin::fixed));
    map.insert("never".to_string(), Builtin::Arity1(builtin::never));

    // Integer operations
    map.insert("int_compare".to_string(), Builtin::Arity2(builtin::int_compare));
    map.insert("int_add".to_string(), Builtin::Arity2(builtin::int_add));
    map.insert("int_subtract".to_string(), Builtin::Arity2(builtin::int_subtract));
    map.insert("int_multiply".to_string(), Builtin::Arity2(builtin::int_multiply));
    map.insert("int_divide".to_string(), Builtin::Arity2(builtin::int_divide));
    map.insert("int_absolute".to_string(), Builtin::Arity1(builtin::int_absolute));
    map.insert("int_parse".to_string(), Builtin::Arity1(builtin::int_parse));
    map.insert("int_to_string".to_string(), Builtin::Arity1(builtin::int_to_string));

    // String operations
    map.insert("string_append".to_string(), Builtin::Arity2(builtin::string_append));
    map.insert("string_split".to_string(), Builtin::Arity2(builtin::string_split));
    map.insert("string_split_once".to_string(), Builtin::Arity2(builtin::string_split_once));
    map.insert("string_replace".to_string(), Builtin::Arity3(builtin::string_replace));
    map.insert("string_uppercase".to_string(), Builtin::Arity1(builtin::string_uppercase));
    map.insert("string_lowercase".to_string(), Builtin::Arity1(builtin::string_lowercase));
    map.insert("string_starts_with".to_string(), Builtin::Arity2(builtin::string_starts_with));
    map.insert("string_ends_with".to_string(), Builtin::Arity2(builtin::string_ends_with));
    map.insert("string_length".to_string(), Builtin::Arity1(builtin::string_length));
    map.insert("string_to_binary".to_string(), Builtin::Arity1(builtin::string_to_binary));
    map.insert("string_from_binary".to_string(), Builtin::Arity1(builtin::string_from_binary));

    // Binary operations
    map.insert("binary_from_integers".to_string(), Builtin::Arity1(builtin::binary_from_integers));
    map.insert("binary_fold".to_string(), Builtin::Arity3(builtin::binary_fold));

    // List operations
    map.insert("list_pop".to_string(), Builtin::Arity1(builtin::list_pop));
    map.insert("list_fold".to_string(), Builtin::Arity3(builtin::list_fold));

    map
}
