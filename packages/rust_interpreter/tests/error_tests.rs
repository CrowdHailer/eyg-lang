// Integration tests for error scenarios and error message quality.
// Covers undefined variables, incorrect types for builtins, missing fields, etc.

use rust_interpreter::interpreter::break_reason::BreakReason;
use rust_interpreter::interpreter::expression;
use rust_interpreter::interpreter::value::Value;
use rust_interpreter::ir::ast::{Expr, Node};
use std::rc::Rc;

/// Execute an EYG expression through the full interpreter
fn run(expr: Expr) -> Result<Rc<Value>, BreakReason> {
    expression::execute(Node(expr, ()), im::Vector::new())
        .map_err(|debug| debug.0)
}

/// Build: (\label -> body) argument
fn apply(func: Expr, argument: Expr) -> Expr {
    Expr::Apply {
        func: Box::new(Node(func, ())),
        argument: Box::new(Node(argument, ())),
    }
}

fn int(n: i64) -> Expr {
    Expr::Integer { value: n }
}
fn str_lit(s: &str) -> Expr {
    Expr::String { value: s.into() }
}
fn builtin(name: &str) -> Expr {
    Expr::Builtin { identifier: name.into() }
}

/// Call a 2-arg builtin: builtin arg1 arg2
fn call2(name: &str, a: Expr, b: Expr) -> Expr {
    apply(apply(builtin(name), a), b)
}

/// Call a 1-arg builtin: builtin arg
fn call1(name: &str, a: Expr) -> Expr {
    apply(builtin(name), a)
}

// ============================================================================
// Error scenarios not covered by spec suites
// ============================================================================

#[test]
fn calling_integer_is_not_a_function() {
    let result = run(apply(int(42), int(1)));
    match result.unwrap_err() {
        BreakReason::NotAFunction(v) => assert!(matches!(*v, Value::Integer(42))),
        other => panic!("expected NotAFunction, got {other}"),
    }
}

#[test]
fn undefined_variable_names_the_variable() {
    let result = run(Expr::Variable { label: "x".into() });
    match result.unwrap_err() {
        BreakReason::UndefinedVariable(name) => assert_eq!(name, "x"),
        other => panic!("expected UndefinedVariable, got {other}"),
    }
}

#[test]
fn undefined_reference_names_the_cid() {
    let result = run(Expr::Reference { identifier: "bafyabc123".into() });
    match result.unwrap_err() {
        BreakReason::UndefinedReference(cid) => assert_eq!(cid, "bafyabc123"),
        other => panic!("expected UndefinedReference, got {other}"),
    }
}

#[test]
fn undefined_release_includes_package_info() {
    let result = run(Expr::Release {
        package: "mypkg".into(),
        release: 3,
        identifier: "bafycid".into(),
    });
    match result.unwrap_err() {
        BreakReason::UndefinedRelease { package, release, cid } => {
            assert_eq!(package, "mypkg");
            assert_eq!(release, 3);
            assert_eq!(cid, "bafycid");
        }
        other => panic!("expected UndefinedRelease, got {other}"),
    }
}

#[test]
fn select_missing_field_names_the_field() {
    let result = run(apply(Expr::Select { label: "missing".into() }, Expr::Empty));
    match result.unwrap_err() {
        BreakReason::MissingField(f) => assert_eq!(f, "missing"),
        other => panic!("expected MissingField, got {other}"),
    }
}

#[test]
fn overwrite_missing_field_names_the_field() {
    let ow = apply(Expr::Overwrite { label: "nope".into() }, int(1));
    let result = run(apply(ow, Expr::Empty));
    match result.unwrap_err() {
        BreakReason::MissingField(f) => assert_eq!(f, "nope"),
        other => panic!("expected MissingField, got {other}"),
    }
}

#[test]
fn nocases_applied_gives_no_match() {
    let tagged = apply(Expr::Tag { label: "X".into() }, int(1));
    let result = run(apply(Expr::NoCases, tagged));
    assert!(matches!(result.unwrap_err(), BreakReason::NoMatch(_)));
}

#[test]
fn perform_without_handler_gives_unhandled_effect() {
    let result = run(apply(Expr::Perform { label: "Ask".into() }, str_lit("question")));
    match result.unwrap_err() {
        BreakReason::UnhandledEffect(label, _) => assert_eq!(label, "Ask"),
        other => panic!("expected UnhandledEffect, got {other}"),
    }
}

#[test]
fn vacant_is_an_error() {
    assert!(matches!(run(Expr::Vacant).unwrap_err(), BreakReason::Vacant));
}

// ============================================================================
// Type error quality: errors tell you what type was expected
// ============================================================================

#[test]
fn type_error_on_int_add_says_expected_integer() {
    // int_add "not a number" 1 -> IncorrectTerm { expected: "Integer" }
    let result = run(call2("int_add", str_lit("nope"), int(1)));
    match result.unwrap_err() {
        BreakReason::IncorrectTerm { expected, .. } => assert_eq!(expected, "Integer"),
        other => panic!("expected IncorrectTerm, got {other}"),
    }
}

#[test]
fn type_error_on_string_append_says_expected_string() {
    let result = run(call2("string_append", int(5), str_lit("x")));
    match result.unwrap_err() {
        BreakReason::IncorrectTerm { expected, .. } => assert_eq!(expected, "String"),
        other => panic!("expected IncorrectTerm, got {other}"),
    }
}

#[test]
fn type_error_on_list_pop_says_expected_list() {
    let result = run(call1("list_pop", int(5)));
    match result.unwrap_err() {
        BreakReason::IncorrectTerm { expected, .. } => assert_eq!(expected, "List"),
        other => panic!("expected IncorrectTerm, got {other}"),
    }
}

#[test]
fn type_error_on_binary_from_integers_says_expected_list() {
    let result = run(call1("binary_from_integers", int(5)));
    match result.unwrap_err() {
        BreakReason::IncorrectTerm { expected, .. } => assert_eq!(expected, "List"),
        other => panic!("expected IncorrectTerm, got {other}"),
    }
}

#[test]
fn never_builtin_always_errors() {
    let result = run(call1("never", int(42)));
    match result.unwrap_err() {
        BreakReason::IncorrectTerm { expected, .. } => assert_eq!(expected, "Never"),
        other => panic!("expected IncorrectTerm, got {other}"),
    }
}
