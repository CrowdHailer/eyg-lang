use clap::Parser;
use rust_interpreter::interpreter::{
    break_reason::BreakReason, expression, value, value_json,
};
use rust_interpreter::ir::ast::Node;
use serde::Deserialize;
use serde_json::Value as JsonValue;
use std::fs;
use std::process;
use std::rc::Rc;

#[derive(Parser, Debug)]
#[command(name = "eyg-run")]
#[command(about = "EYG Rust Interpreter - Execute EYG programs", long_about = None)]
struct Args {
    /// Path to EYG program file (dag-json IR)
    file: String,

    /// Path to JSON file containing effect handlers
    #[arg(long)]
    effects: Option<String>,
}

#[derive(Debug, Deserialize)]
struct EffectHandler {
    label: String,
    #[allow(dead_code)]
    lift: JsonValue,
    reply: JsonValue,
}

fn read_file(path: &str) -> String {
    match fs::read_to_string(path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Error reading file '{}': {}", path, e);
            process::exit(1);
        }
    }
}

fn load_node(path: &str) -> Node {
    let contents = read_file(path);
    match serde_json::from_str(&contents) {
        Ok(n) => n,
        Err(e) => {
            eprintln!("Error parsing JSON: {}", e);
            process::exit(1);
        }
    }
}

fn load_effects(path: &str) -> Vec<EffectHandler> {
    let contents = read_file(path);
    match serde_json::from_str(&contents) {
        Ok(h) => h,
        Err(e) => {
            eprintln!("Error parsing effects JSON: {}", e);
            process::exit(1);
        }
    }
}

/// Execute a node, handling Log effects automatically and explicit effect handlers.
fn run(node: Node, effect_handlers: &[EffectHandler]) {
    let mut result = expression::execute(node, im::Vector::new());

    for handler in effect_handlers {
        match &result {
            Err(debug) => {
                let (reason, _meta, env, stack) = &**debug;
                match reason {
                    BreakReason::UnhandledEffect(label, _lift_value) => {
                        if label != &handler.label {
                            eprintln!(
                                "Error: Expected effect '{}', but got '{}'",
                                handler.label, label
                            );
                            process::exit(1);
                        }
                        let reply = Rc::new(value_json::deserialize_value(&handler.reply));
                        result = expression::resume(reply, env.clone(), stack.clone());
                    }
                    _ => {
                        eprintln!("Error: Expected UnhandledEffect, got: {}", reason);
                        process::exit(1);
                    }
                }
            }
            Ok(_) => {
                eprintln!(
                    "Error: Expected UnhandledEffect for '{}', but execution succeeded",
                    handler.label
                );
                process::exit(1);
            }
        }
    }

    // Handle Log effects in a loop (built-in extrinsic)
    while let Err(debug) = &result {
        let (reason, _meta, env, stack) = &**debug;
        if let BreakReason::UnhandledEffect(label, lift_value) = reason
            && label == "Log"
        {
            eprintln!("{}", lift_value);
            let reply = Rc::new(value::unit());
            result = expression::resume(reply, env.clone(), stack.clone());
        } else {
            break;
        }
    }

    match result {
        Ok(val) => {
            println!("{}", val);
        }
        Err(debug) => {
            let (reason, _, _, _) = *debug;
            eprintln!("Error: {}", reason);
            process::exit(1);
        }
    }
}

fn main() {
    let args = Args::parse();
    let node = load_node(&args.file);

    let handlers = args
        .effects
        .as_deref()
        .map(load_effects)
        .unwrap_or_default();
    run(node, &handlers);
}
