// Test IR deserialization using spec/ir_suite.json

use rust_interpreter::ir::{Expr, Node};
use serde::Deserialize;
use std::fs;

#[derive(Debug, Deserialize)]
struct Fixture {
    name: String,
    source: serde_json::Value,
    #[allow(dead_code)]
    cid: String,
}

#[test]
fn test_ir_suite() {
    // Read the test suite
    let content = fs::read_to_string("../../spec/ir_suite.json")
        .expect("Failed to read spec/ir_suite.json");
    
    let fixtures: Vec<Fixture> = serde_json::from_str(&content)
        .expect("Failed to parse ir_suite.json");
    
    for fixture in fixtures {
        println!("Testing: {}", fixture.name);
        
        // Try to deserialize the source as a Node
        let result: Result<Node, _> = serde_json::from_value(fixture.source.clone());
        
        match result {
            Ok(node) => {
                println!("  ✓ Successfully parsed: {:?}", node.0);
            }
            Err(e) => {
                panic!("Failed to parse '{}': {}\nSource: {}", 
                    fixture.name, e, serde_json::to_string_pretty(&fixture.source).unwrap());
            }
        }
    }
}

#[test]
fn test_simple_variable() {
    let json = r#"{"0":"v","l":"foo"}"#;
    let node: Node = serde_json::from_str(json).expect("Failed to parse variable");
    
    match &node.0 {
        Expr::Variable { label } => {
            assert_eq!(label, "foo");
        }
        _ => panic!("Expected Variable, got {:?}", node.0),
    }
}

#[test]
fn test_simple_integer() {
    let json = r#"{"0":"i","v":42}"#;
    let node: Node = serde_json::from_str(json).expect("Failed to parse integer");
    
    match &node.0 {
        Expr::Integer { value } => {
            assert_eq!(*value, 42);
        }
        _ => panic!("Expected Integer, got {:?}", node.0),
    }
}

#[test]
fn test_simple_string() {
    let json = r#"{"0":"s","v":"hello"}"#;
    let node: Node = serde_json::from_str(json).expect("Failed to parse string");
    
    match &node.0 {
        Expr::String { value } => {
            assert_eq!(value, "hello");
        }
        _ => panic!("Expected String, got {:?}", node.0),
    }
}

#[test]
fn test_tail() {
    let json = r#"{"0":"ta"}"#;
    let node: Node = serde_json::from_str(json).expect("Failed to parse tail");
    
    match &node.0 {
        Expr::Tail => {}
        _ => panic!("Expected Tail, got {:?}", node.0),
    }
}

#[test]
fn test_binary() {
    let json = r#"{"0":"x","v":{"/":{"bytes":"AQ"}}}"#;
    let node: Node = serde_json::from_str(json).expect("Failed to parse binary");
    
    match &node.0 {
        Expr::Binary { value } => {
            assert_eq!(value, &vec![1]);
        }
        _ => panic!("Expected Binary, got {:?}", node.0),
    }
}

#[test]
fn test_cid_reference() {
    let json = r##"{"0":"#","l":{"/":"baguqeeraqyvjt4lhfr66jw66yhg37xaj7tvdde5pifx7eqdq2a4zgzpffwaq"}}"##;
    let node: Node = serde_json::from_str(json).expect("Failed to parse reference");

    match &node.0 {
        Expr::Reference { identifier } => {
            assert_eq!(identifier, "baguqeeraqyvjt4lhfr66jw66yhg37xaj7tvdde5pifx7eqdq2a4zgzpffwaq");
        }
        _ => panic!("Expected Reference, got {:?}", node.0),
    }
}

#[test]
fn test_lambda() {
    let json = r#"{"0":"f","l":"x","b":{"0":"v","l":"x"}}"#;
    let node: Node = serde_json::from_str(json).expect("Failed to parse lambda");
    
    match &node.0 {
        Expr::Lambda { label, body } => {
            assert_eq!(label, "x");
            match &body.0 {
                Expr::Variable { label: var_label } => {
                    assert_eq!(var_label, "x");
                }
                _ => panic!("Expected Variable in lambda body"),
            }
        }
        _ => panic!("Expected Lambda, got {:?}", node.0),
    }
}

