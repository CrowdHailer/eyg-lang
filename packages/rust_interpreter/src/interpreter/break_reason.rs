// Error / break reasons
// Mirrors packages/gleam_interpreter/src/eyg/interpreter/break.gleam

use super::value::Value;
use std::fmt;

/// Reasons why evaluation might break/fail.
/// Mirrors the Reason(m, c) type from break.gleam.
/// Values are boxed to reduce the size of the enum.
#[derive(Debug, Clone)]
pub enum BreakReason {
    NotAFunction(Box<Value>),
    UndefinedVariable(String),
    UndefinedBuiltin(String),
    UndefinedReference(String),
    UndefinedRelease {
        package: String,
        release: i64,
        cid: String,
    },
    Vacant,
    NoMatch(Box<Value>),
    UnhandledEffect(String, Box<Value>),
    IncorrectTerm {
        expected: String,
        got: Box<Value>,
    },
    MissingField(String),
}

impl fmt::Display for BreakReason {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BreakReason::NotAFunction(val) => {
                write!(f, "Not a function: {}", val)
            }
            BreakReason::UndefinedVariable(name) => {
                write!(f, "Undefined variable: {}", name)
            }
            BreakReason::UndefinedBuiltin(name) => {
                write!(f, "Undefined builtin: {}", name)
            }
            BreakReason::UndefinedReference(cid) => {
                write!(f, "Undefined reference: {}", cid)
            }
            BreakReason::UndefinedRelease { package, release, cid } => {
                write!(f, "Undefined release: {}/{} ({})", package, release, cid)
            }
            BreakReason::Vacant => {
                write!(f, "Vacant")
            }
            BreakReason::NoMatch(val) => {
                write!(f, "No match for: {}", val)
            }
            BreakReason::UnhandledEffect(label, val) => {
                write!(f, "Unhandled effect '{}' with value: {}", label, val)
            }
            BreakReason::IncorrectTerm { expected, got } => {
                write!(f, "Incorrect term: expected {}, got {}", expected, got)
            }
            BreakReason::MissingField(field) => {
                write!(f, "Missing field: {}", field)
            }
        }
    }
}
