// JSON serialization/deserialization for Value
// Used by CLI and tests to convert between JSON and runtime values

use super::value::Value;
use im;
use serde_json::Value as JsonValue;
use std::rc::Rc;

/// Deserialize a JSON value into a runtime Value
pub fn deserialize_value(json: &JsonValue) -> Value {
    if let Some(i) = json.get("integer") {
        return Value::Integer(i.as_i64().expect("integer should be i64"));
    }
    if let Some(s) = json.get("string") {
        return Value::Str(s.as_str().expect("string should be str").to_string());
    }
    if let Some(b) = json.get("binary") {
        // Binary is encoded as dag-json: {"/":{bytes":"<base64>"}}
        let dag_obj = b.as_object().expect("binary should be object");
        let bytes_obj = dag_obj
            .get("/")
            .expect("binary should have / field")
            .as_object()
            .expect("/ should be object");
        let bytes_str = bytes_obj
            .get("bytes")
            .expect("binary should have bytes field")
            .as_str()
            .expect("bytes should be string");
        // Use base64 engine for decoding
        use base64::Engine;
        let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(bytes_str)
            .expect("bytes should be valid base64");
        return Value::Binary(bytes);
    }
    if let Some(list) = json.get("list") {
        let items: Vec<Rc<Value>> = list
            .as_array()
            .expect("list should be array")
            .iter()
            .map(|v| Rc::new(deserialize_value(v)))
            .collect();
        return Value::LinkedList(items);
    }
    if let Some(record) = json.get("record") {
        let fields: im::HashMap<String, Rc<Value>> = record
            .as_object()
            .expect("record should be object")
            .iter()
            .map(|(k, v)| (k.clone(), Rc::new(deserialize_value(v))))
            .collect();
        return Value::Record(fields);
    }
    if let Some(tagged) = json.get("tagged") {
        let label = tagged
            .get("label")
            .expect("tagged should have label")
            .as_str()
            .expect("label should be string")
            .to_string();
        let value = Rc::new(deserialize_value(
            tagged.get("value").expect("tagged should have value"),
        ));
        return Value::Tagged { label, value };
    }
    panic!("Unknown value type: {:?}", json);
}

