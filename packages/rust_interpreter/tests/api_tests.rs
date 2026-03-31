// Integration tests for the expression::call and expression::resume public APIs.
// These APIs allow embedding the EYG interpreter in a larger Rust program.

use rust_interpreter::interpreter::expression;
use rust_interpreter::interpreter::value::{Switch, Value};
use std::rc::Rc;
use im;

#[test]
fn call_api_applies_function_to_args() {
    let tag = Rc::new(Value::Partial(Switch::Tag("Ok".into()), vec![]));
    let result = expression::call(tag, vec![(Rc::new(Value::Integer(42)), ())]);
    match result.unwrap().as_ref() {
        Value::Tagged { label, value } => {
            assert_eq!(label, "Ok");
            assert!(matches!(value.as_ref(), Value::Integer(42)));
        }
        other => panic!("expected Tagged, got {other}"),
    }
}

#[test]
fn call_api_select_from_record() {
    let select = Rc::new(Value::Partial(Switch::Select("x".into()), vec![]));
    let mut fields = im::HashMap::new();
    fields.insert("x".to_string(), Rc::new(Value::Integer(10)));
    let result = expression::call(select, vec![(Rc::new(Value::Record(fields)), ())]);
    assert!(matches!(result.unwrap().as_ref(), Value::Integer(10)));
}

#[test]
fn call_api_non_function_errors() {
    let result = expression::call(
        Rc::new(Value::Integer(42)),
        vec![(Rc::new(Value::Integer(1)), ())],
    );
    assert!(result.is_err());
}
