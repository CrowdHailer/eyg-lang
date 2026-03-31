// Serialization and deserialization invariants
// Covers IR (Node, Expr) and runtime Value JSON roundtrips.

use rust_interpreter::interpreter::value::{Value, Switch};
use rust_interpreter::interpreter::value_json;
use rust_interpreter::ir::ast::{Expr, Node};
use serde_json;
use base64::Engine;

// ============================================================================
// IR serialization roundtrips (real invariant: serialize then deserialize = identity)
// ============================================================================

#[test]
fn roundtrip_integer() {
    let n = Node(Expr::Integer { value: 42 }, ());
    let json = serde_json::to_string(&n).unwrap();
    assert_eq!(serde_json::from_str::<Node>(&json).unwrap(), n);
}

#[test]
fn roundtrip_string() {
    let n = Node(Expr::String { value: "hello".into() }, ());
    let json = serde_json::to_string(&n).unwrap();
    assert_eq!(serde_json::from_str::<Node>(&json).unwrap(), n);
}

#[test]
fn roundtrip_lambda() {
    let n = Node(
        Expr::Lambda {
            label: "x".into(),
            body: Box::new(Node(Expr::Variable { label: "x".into() }, ())),
        },
        (),
    );
    let json = serde_json::to_string(&n).unwrap();
    assert_eq!(serde_json::from_str::<Node>(&json).unwrap(), n);
}

#[test]
fn roundtrip_binary() {
    let n = Node(Expr::Binary { value: vec![0, 127, 255] }, ());
    let json = serde_json::to_value(&n).unwrap();
    assert_eq!(serde_json::from_value::<Node>(json).unwrap(), n);
}

#[test]
fn roundtrip_empty_binary() {
    let n = Node(Expr::Binary { value: vec![] }, ());
    let json = serde_json::to_value(&n).unwrap();
    assert_eq!(serde_json::from_value::<Node>(json).unwrap(), n);
}

#[test]
fn roundtrip_reference() {
    let n = Node(Expr::Reference { identifier: "bafytest".into() }, ());
    let json = serde_json::to_string(&n).unwrap();
    assert_eq!(serde_json::from_str::<Node>(&json).unwrap(), n);
}

#[test]
fn roundtrip_release() {
    let n = Node(
        Expr::Release {
            package: "mypkg".into(),
            release: 1,
            identifier: "bafycid".into(),
        },
        (),
    );
    let json = serde_json::to_string(&n).unwrap();
    assert_eq!(serde_json::from_str::<Node>(&json).unwrap(), n);
}

#[test]
fn roundtrip_tail() {
    let n = Node(Expr::Tail, ());
    let json = serde_json::to_string(&n).unwrap();
    assert_eq!(serde_json::from_str::<Node>(&json).unwrap(), n);
}

// ============================================================================
// value_json deserialization (behavior: JSON -> runtime Value)
// ============================================================================

#[test]
fn deserialize_json_binary() {
    let encoded = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode([1, 2, 3]);
    let json = serde_json::json!({"binary": {"/": {"bytes": encoded}}});
    assert!(matches!(value_json::deserialize_value(&json), Value::Binary(b) if b == vec![1, 2, 3]));
}

#[test]
fn deserialize_json_list() {
    let json = serde_json::json!({"list": [{"integer": 1}, {"integer": 2}]});
    match value_json::deserialize_value(&json) {
        Value::LinkedList(items) => {
            assert_eq!(items.len(), 2);
            assert!(matches!(items[0].as_ref(), Value::Integer(1)));
            assert!(matches!(items[1].as_ref(), Value::Integer(2)));
        }
        other => panic!("expected list, got {other:?}"),
    }
}

#[test]
fn deserialize_json_record() {
    let json = serde_json::json!({"record": {"x": {"integer": 1}, "y": {"string": "hi"}}});
    match value_json::deserialize_value(&json) {
        Value::Record(fields) => {
            assert!(matches!(fields.get("x").unwrap().as_ref(), Value::Integer(1)));
            assert!(matches!(fields.get("y").unwrap().as_ref(), Value::Str(s) if s == "hi"));
        }
        other => panic!("expected record, got {other:?}"),
    }
}

#[test]
fn deserialize_json_tagged() {
    let json = serde_json::json!({"tagged": {"label": "Ok", "value": {"integer": 42}}});
    match value_json::deserialize_value(&json) {
        Value::Tagged { label, value } => {
            assert_eq!(label, "Ok");
            assert!(matches!(value.as_ref(), Value::Integer(42)));
        }
        other => panic!("expected tagged, got {other:?}"),
    }
}

#[test]
#[should_panic(expected = "Unknown value type")]
fn deserialize_json_unknown_type_panics() {
    value_json::deserialize_value(&serde_json::json!({"garbage": true}));
}
