// Value casting helpers
// Mirrors packages/gleam_interpreter/src/eyg/interpreter/cast.gleam

use super::break_reason::BreakReason;
use super::value::Value;
use im;
use std::rc::Rc;

/// Cast a value to an integer
pub fn as_integer(value: &Value) -> Result<i64, BreakReason> {
    match value {
        Value::Integer(v) => Ok(*v),
        _ => Err(BreakReason::IncorrectTerm {
            expected: "Integer".to_string(),
            got: Box::new(value.clone()),
        }),
    }
}

/// Cast a value to a string
pub fn as_string(value: &Value) -> Result<&str, BreakReason> {
    match value {
        Value::Str(v) => Ok(v.as_str()),
        _ => Err(BreakReason::IncorrectTerm {
            expected: "String".to_string(),
            got: Box::new(value.clone()),
        }),
    }
}

/// Cast a value to binary data
pub fn as_binary(value: &Value) -> Result<&[u8], BreakReason> {
    match value {
        Value::Binary(v) => Ok(v.as_slice()),
        _ => Err(BreakReason::IncorrectTerm {
            expected: "Binary".to_string(),
            got: Box::new(value.clone()),
        }),
    }
}

/// Cast a value to a list
pub fn as_list(value: &Value) -> Result<&Vec<Rc<Value>>, BreakReason> {
    match value {
        Value::LinkedList(elements) => Ok(elements),
        _ => Err(BreakReason::IncorrectTerm {
            expected: "List".to_string(),
            got: Box::new(value.clone()),
        }),
    }
}

/// Cast a value to a record
pub fn as_record(value: &Value) -> Result<&im::HashMap<String, Rc<Value>>, BreakReason> {
    match value {
        Value::Record(fields) => Ok(fields),
        _ => Err(BreakReason::IncorrectTerm {
            expected: "Record".to_string(),
            got: Box::new(value.clone()),
        }),
    }
}

/// Cast a value to a tagged value
pub fn as_tagged(value: &Value) -> Result<(&str, &Rc<Value>), BreakReason> {
    match value {
        Value::Tagged { label, value } => Ok((label.as_str(), value)),
        _ => Err(BreakReason::IncorrectTerm {
            expected: "Tagged".to_string(),
            got: Box::new(value.clone()),
        }),
    }
}
