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
    let mut handler_idx = 0;

    while let Err(debug) = &result {
        let (reason, _meta, env, stack) = &**debug;
        if let BreakReason::UnhandledEffect(label, lift_value) = reason {
            if label == "Log" {
                eprintln!("{}", lift_value);
                let reply = Rc::new(value::unit());
                result = expression::resume(reply, env.clone(), stack.clone());
                continue;
            }
            if handler_idx < effect_handlers.len() {
                let handler = &effect_handlers[handler_idx];
                if label == &handler.label {
                    let reply = Rc::new(value_json::deserialize_value(&handler.reply));
                    result = expression::resume(reply, env.clone(), stack.clone());
                    handler_idx += 1;
                    continue;
                }
            }
        }
        break;
    }

    match result {
        Ok(val) => {
            if handler_idx < effect_handlers.len() {
                eprintln!(
                    "Error: Expected UnhandledEffect for '{}', but execution succeeded",
                    effect_handlers[handler_idx].label
                );
                process::exit(1);
            }
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
