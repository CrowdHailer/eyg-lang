// CLI integration tests
use std::fs;
use std::process::Command;

fn eyg_run() -> Command {
    Command::new("./target/debug/eyg-run")
}

#[test]
fn test_cli_integer() {
    let json = r#"{"0":"i","v":42}"#;
    let temp_file = "/tmp/eyg_test_integer.json";
    fs::write(temp_file, json).unwrap();

    let output = eyg_run()
        .arg(temp_file)
        .output()
        .expect("Failed to execute command");

    assert!(output.status.success());
    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "42");
}

#[test]
fn test_cli_string() {
    let json = r#"{"0":"s","v":"hello"}"#;
    let temp_file = "/tmp/eyg_test_string.json";
    fs::write(temp_file, json).unwrap();

    let output = eyg_run()
        .arg(temp_file)
        .output()
        .expect("Failed to execute command");

    assert!(output.status.success());
    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "\"hello\"");
}

#[test]
fn test_cli_error() {
    let json = r#"{"0":"v","l":"x"}"#;
    let temp_file = "/tmp/eyg_test_error.json";
    fs::write(temp_file, json).unwrap();

    let output = eyg_run()
        .arg(temp_file)
        .output()
        .expect("Failed to execute command");

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("Undefined variable: x"));
}

#[test]
fn test_cli_lambda_application() {
    let json = r#"{
        "0": "a",
        "f": {
            "0": "f",
            "l": "x",
            "b": {
                "0": "v",
                "l": "x"
            }
        },
        "a": {
            "0": "i",
            "v": 42
        }
    }"#;
    let temp_file = "/tmp/eyg_test_lambda.json";
    fs::write(temp_file, json).unwrap();

    let output = eyg_run()
        .arg(temp_file)
        .output()
        .expect("Failed to execute command");

    assert!(output.status.success());
    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "42");
}

#[test]
fn test_cli_file_not_found() {
    let output = eyg_run()
        .arg("/tmp/nonexistent_file.json")
        .output()
        .expect("Failed to execute command");

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("Error reading file"));
}

#[test]
fn test_cli_invalid_json() {
    let json = r#"not valid json"#;
    let temp_file = "/tmp/eyg_test_invalid.json";
    fs::write(temp_file, json).unwrap();

    let output = eyg_run()
        .arg(temp_file)
        .output()
        .expect("Failed to execute command");

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("Error parsing JSON"));
}

#[test]
fn test_cli_with_effects() {
    // Test program that performs two effects: Foo(1) -> 2, then Bar(2) -> 34
    let program_json = r#"{
  "0": "l",
  "l": "a",
  "t": {
    "0": "a",
    "a": {
      "0": "v",
      "l": "a"
    },
    "f": {
      "0": "p",
      "l": "Bar"
    }
  },
  "v": {
    "0": "a",
    "a": {
      "0": "i",
      "v": 1
    },
    "f": {
      "0": "p",
      "l": "Foo"
    }
  }
}"#;

    let effects_json = r#"[
  {
    "label": "Foo",
    "lift": {
      "integer": 1
    },
    "reply": {
      "integer": 2
    }
  },
  {
    "label": "Bar",
    "lift": {
      "integer": 2
    },
    "reply": {
      "integer": 34
    }
  }
]"#;

    let program_file = "/tmp/eyg_test_effects_program.json";
    let effects_file = "/tmp/eyg_test_effects_handlers.json";
    fs::write(program_file, program_json).unwrap();
    fs::write(effects_file, effects_json).unwrap();

    let output = eyg_run()
        .args([program_file, "--effects", effects_file])
        .output()
        .expect("Failed to execute command");

    assert!(
        output.status.success(),
        "Command failed with stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "34");
}

#[test]
fn test_cli_unhandled_effect() {
    // Test program that performs an effect without a handler
    let program_json = r#"{
  "0": "a",
  "a": {
    "0": "i",
    "v": 1
  },
  "f": {
    "0": "p",
    "l": "Foo"
  }
}"#;

    let program_file = "/tmp/eyg_test_unhandled_effect.json";
    fs::write(program_file, program_json).unwrap();

    let output = eyg_run()
        .arg(program_file)
        .output()
        .expect("Failed to execute command");

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("Unhandled effect 'Foo'"));
}


