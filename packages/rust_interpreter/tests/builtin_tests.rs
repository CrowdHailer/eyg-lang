// Simple unit tests for builtin functions
use rust_interpreter::interpreter::builtin;
use rust_interpreter::interpreter::state::{Env, Stack};
use rust_interpreter::interpreter::value::Value;
use im;
use std::rc::Rc;

fn empty_env() -> Env {
    Env {
        scope: im::Vector::new(),
        references: im::HashMap::new(),
        builtins: im::HashMap::new(),
    }
}

fn empty_stack() -> Stack {
    Stack::Empty(im::HashMap::new())
}

#[test]
fn test_int_add() {
    let left = Rc::new(Value::Integer(5));
    let right = Rc::new(Value::Integer(3));
    let result = builtin::int_add(&left, &right, (), empty_env(), empty_stack());

    assert!(result.is_ok());
    let (control, _, _) = result.unwrap();
    match control {
        rust_interpreter::interpreter::state::Control::Val(v) => {
            match v.as_ref() {
                Value::Integer(n) => assert_eq!(*n, 8),
                _ => panic!("Expected Integer value"),
            }
        }
        _ => panic!("Expected Val control"),
    }
}

#[test]
fn test_int_subtract() {
    let left = Rc::new(Value::Integer(10));
    let right = Rc::new(Value::Integer(3));
    let result = builtin::int_subtract(&left, &right, (), empty_env(), empty_stack());
    
    assert!(result.is_ok());
    let (control, _, _) = result.unwrap();
    match control {
        rust_interpreter::interpreter::state::Control::Val(v) => {
            match v.as_ref() {
                Value::Integer(n) => assert_eq!(*n, 7),
                _ => panic!("Expected Integer value"),
            }
        }
        _ => panic!("Expected Val control"),
    }
}

#[test]
fn test_int_multiply() {
    let left = Rc::new(Value::Integer(4));
    let right = Rc::new(Value::Integer(5));
    let result = builtin::int_multiply(&left, &right, (), empty_env(), empty_stack());

    assert!(result.is_ok());
    let (control, _, _) = result.unwrap();
    match control {
        rust_interpreter::interpreter::state::Control::Val(v) => {
            match v.as_ref() {
                Value::Integer(n) => assert_eq!(*n, 20),
                _ => panic!("Expected Integer value"),
            }
        }
        _ => panic!("Expected Val control"),
    }
}

#[test]
fn test_int_divide_success() {
    let left = Rc::new(Value::Integer(20));
    let right = Rc::new(Value::Integer(4));
    let result = builtin::int_divide(&left, &right, (), empty_env(), empty_stack());

    assert!(result.is_ok());
    let (control, _, _) = result.unwrap();
    match control {
        rust_interpreter::interpreter::state::Control::Val(v) => {
            match v.as_ref() {
                Value::Tagged { label, value } => {
                    assert_eq!(label, "Ok");
                    match value.as_ref() {
                        Value::Integer(n) => assert_eq!(*n, 5),
                        _ => panic!("Expected Integer in Ok"),
                    }
                }
                _ => panic!("Expected Tagged value"),
            }
        }
        _ => panic!("Expected Val control"),
    }
}

#[test]
fn test_int_divide_by_zero() {
    let left = Rc::new(Value::Integer(20));
    let right = Rc::new(Value::Integer(0));
    let result = builtin::int_divide(&left, &right, (), empty_env(), empty_stack());
    
    assert!(result.is_ok());
    let (control, _, _) = result.unwrap();
    match control {
        rust_interpreter::interpreter::state::Control::Val(v) => {
            match v.as_ref() {
                Value::Tagged { label, .. } => {
                    assert_eq!(label, "Error");
                }
                _ => panic!("Expected Tagged value"),
            }
        }
        _ => panic!("Expected Val control"),
    }
}

#[test]
fn test_string_append() {
    let left = Rc::new(Value::Str("Hello, ".to_string()));
    let right = Rc::new(Value::Str("World!".to_string()));
    let result = builtin::string_append(&left, &right, (), empty_env(), empty_stack());

    assert!(result.is_ok());
    let (control, _, _) = result.unwrap();
    match control {
        rust_interpreter::interpreter::state::Control::Val(v) => {
            match v.as_ref() {
                Value::Str(s) => assert_eq!(s, "Hello, World!"),
                _ => panic!("Expected Str value"),
            }
        }
        _ => panic!("Expected Val control"),
    }
}

#[test]
fn test_equal_true() {
    let left = Rc::new(Value::Integer(42));
    let right = Rc::new(Value::Integer(42));
    let result = builtin::equal(&left, &right, (), empty_env(), empty_stack());

    assert!(result.is_ok());
    let (control, _, _) = result.unwrap();
    match control {
        rust_interpreter::interpreter::state::Control::Val(v) => {
            match v.as_ref() {
                Value::Tagged { label, .. } => assert_eq!(label, "True"),
                _ => panic!("Expected Tagged value"),
            }
        }
        _ => panic!("Expected Val control"),
    }
}

