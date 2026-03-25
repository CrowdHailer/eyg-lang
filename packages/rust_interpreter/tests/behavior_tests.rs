// Behavioral integration tests for the Rust interpreter.
// These tests focus on end-to-end success scenarios for language features
// (closures, recursion, data structures, builtins integration) that are not 
// already covered by the shared spec suites.

use rust_interpreter::interpreter::break_reason::BreakReason;
use rust_interpreter::interpreter::expression;

use rust_interpreter::interpreter::value::{Switch, Value};
use rust_interpreter::interpreter::value_json;
use rust_interpreter::ir::ast::{Expr, Node};

use std::rc::Rc;

/// Execute an EYG expression through the full interpreter
fn run(expr: Expr) -> Result<Rc<Value>, BreakReason> {
    expression::execute(Node(expr, ()), im::Vector::new())
        .map_err(|debug| debug.0)
}

/// Build: (\label -> body) argument
fn apply(func: Expr, argument: Expr) -> Expr {
    Expr::Apply {
        func: Box::new(Node(func, ())),
        argument: Box::new(Node(argument, ())),
    }
}

/// Build: let label = definition in body
fn let_in(label: &str, definition: Expr, body: Expr) -> Expr {
    Expr::Let {
        label: label.into(),
        definition: Box::new(Node(definition, ())),
        body: Box::new(Node(body, ())),
    }
}

/// Build: \label -> body
fn lambda(label: &str, body: Expr) -> Expr {
    Expr::Lambda {
        label: label.into(),
        body: Box::new(Node(body, ())),
    }
}

fn var(name: &str) -> Expr {
    Expr::Variable { label: name.into() }
}
fn int(n: i64) -> Expr {
    Expr::Integer { value: n }
}
fn str_lit(s: &str) -> Expr {
    Expr::String { value: s.into() }
}
fn builtin(name: &str) -> Expr {
    Expr::Builtin { identifier: name.into() }
}

/// Call a 2-arg builtin: builtin arg1 arg2
fn call2(name: &str, a: Expr, b: Expr) -> Expr {
    apply(apply(builtin(name), a), b)
}

/// Call a 1-arg builtin: builtin arg
fn call1(name: &str, a: Expr) -> Expr {
    apply(builtin(name), a)
}

// ============================================================================
// End-to-end programs: closures, recursion, data structures
// ============================================================================

#[test]
fn closure_captures_outer_variable() {
    // let x = 10 in let f = \y -> int_add x y in f 5
    // Expected: 15
    let program = let_in(
        "x",
        int(10),
        let_in(
            "f",
            lambda("y", call2("int_add", var("x"), var("y"))),
            apply(var("f"), int(5)),
        ),
    );
    let v = run(program).unwrap();
    assert!(matches!(v.as_ref(), Value::Integer(15)));
}

#[test]
fn higher_order_function() {
    // let apply_twice = \f -> \x -> f (f x)
    // let inc = \n -> int_add n 1
    // apply_twice inc 3
    // Expected: 5
    let program = let_in(
        "apply_twice",
        lambda("f", lambda("x", apply(var("f"), apply(var("f"), var("x"))))),
        let_in(
            "inc",
            lambda("n", call2("int_add", var("n"), int(1))),
            apply(apply(var("apply_twice"), var("inc")), int(3)),
        ),
    );
    let v = run(program).unwrap();
    assert!(matches!(v.as_ref(), Value::Integer(5)));
}

#[test]
fn build_and_select_nested_record() {
    // let r = (+y) 20 ((+x) 10 {})
    // .x r
    // Expected: 10
    let build_inner = apply(apply(Expr::Extend { label: "x".into() }, int(10)), Expr::Empty);
    let build_outer = apply(apply(Expr::Extend { label: "y".into() }, int(20)), build_inner);
    let program = let_in(
        "r",
        build_outer,
        apply(Expr::Select { label: "x".into() }, var("r")),
    );
    let v = run(program).unwrap();
    assert!(matches!(v.as_ref(), Value::Integer(10)));
}

#[test]
fn cons_multi_element_list() {
    // cons 1 (cons 2 (cons 3 []))
    let list = apply(
        apply(Expr::Cons, int(1)),
        apply(apply(Expr::Cons, int(2)), apply(apply(Expr::Cons, int(3)), Expr::Tail)),
    );
    let v = run(list).unwrap();
    match v.as_ref() {
        Value::LinkedList(items) => {
            assert_eq!(items.len(), 3);
            assert!(matches!(items[0].as_ref(), Value::Integer(1)));
            assert!(matches!(items[1].as_ref(), Value::Integer(2)));
            assert!(matches!(items[2].as_ref(), Value::Integer(3)));
        }
        other => panic!("expected 3-element list, got {other}"),
    }
}

#[test]
fn match_chain_two_cases_with_fallthrough() {
    // case "A" (\v -> v) (case "B" (\v -> int_add v 100) nocases)
    // applied to B(7) -> 107
    let inner_case = apply(
        apply(
            Expr::Case { label: "B".into() },
            lambda("v", call2("int_add", var("v"), int(100))),
        ),
        Expr::NoCases,
    );
    let outer_case = apply(
        apply(
            Expr::Case { label: "A".into() },
            lambda("v", var("v")),
        ),
        inner_case,
    );
    let tagged_b = apply(Expr::Tag { label: "B".into() }, int(7));
    let v = run(apply(outer_case, tagged_b)).unwrap();
    assert!(matches!(v.as_ref(), Value::Integer(107)));
}

#[test]
fn string_pipeline() {
    // string_uppercase (string_replace "hello world" "world" "rust")
    // Expected: "HELLO RUST"
    let replaced = apply(
        apply(
            apply(builtin("string_replace"), str_lit("hello world")),
            str_lit("world"),
        ),
        str_lit("rust"),
    );
    let program = call1("string_uppercase", replaced);
    let v = run(program).unwrap();
    assert!(matches!(v.as_ref(), Value::Str(s) if s == "HELLO RUST"));
}

#[test]
fn int_to_string_then_parse_roundtrip() {
    // int_parse (int_to_string -42)
    // Expected: Ok(-42)
    let program = call1("int_parse", call1("int_to_string", int(-42)));
    let v = run(program).unwrap();
    match v.as_ref() {
        Value::Tagged { label, value } => {
            assert_eq!(label, "Ok");
            assert!(matches!(value.as_ref(), Value::Integer(-42)));
        }
        other => panic!("expected Ok(-42), got {other}"),
    }
}

#[test]
fn string_to_binary_and_back() {
    // string_from_binary (string_to_binary "café")
    // Expected: Ok("café")
    let program = call1("string_from_binary", call1("string_to_binary", str_lit("café")));
    let v = run(program).unwrap();
    match v.as_ref() {
        Value::Tagged { label, value } => {
            assert_eq!(label, "Ok");
            assert!(matches!(value.as_ref(), Value::Str(s) if s == "café"));
        }
        other => panic!("expected Ok(\"café\"), got {other}"),
    }
}

// ============================================================================
// Equality on complex types (exercises Value::equals through the `equal` builtin)
// ============================================================================

#[test]
fn equal_lists_are_equal() {
    // equal (cons 1 (cons 2 [])) (cons 1 (cons 2 []))
    let mk_list = || {
        apply(
            apply(Expr::Cons, int(1)),
            apply(apply(Expr::Cons, int(2)), Expr::Tail),
        )
    };
    let program = call2("equal", mk_list(), mk_list());
    match run(program).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "True"),
        other => panic!("expected True, got {other}"),
    }
}

#[test]
fn different_lists_are_not_equal() {
    let list_a = apply(apply(Expr::Cons, int(1)), Expr::Tail);
    let list_b = apply(apply(Expr::Cons, int(2)), Expr::Tail);
    let program = call2("equal", list_a, list_b);
    match run(program).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "False"),
        other => panic!("expected False, got {other}"),
    }
}

#[test]
fn equal_records_are_equal() {
    let mk_rec = || apply(apply(Expr::Extend { label: "x".into() }, int(1)), Expr::Empty);
    let program = call2("equal", mk_rec(), mk_rec());
    match run(program).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "True"),
        other => panic!("expected True, got {other}"),
    }
}

#[test]
fn different_records_are_not_equal() {
    let rec_a = apply(apply(Expr::Extend { label: "x".into() }, int(1)), Expr::Empty);
    let rec_b = apply(apply(Expr::Extend { label: "x".into() }, int(2)), Expr::Empty);
    let program = call2("equal", rec_a, rec_b);
    match run(program).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "False"),
        other => panic!("expected False, got {other}"),
    }
}

#[test]
fn equal_tagged_values_are_equal() {
    let mk_tagged = || apply(Expr::Tag { label: "Ok".into() }, int(42));
    let program = call2("equal", mk_tagged(), mk_tagged());
    match run(program).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "True"),
        other => panic!("expected True, got {other}"),
    }
}

#[test]
fn different_tagged_labels_not_equal() {
    let a = apply(Expr::Tag { label: "Ok".into() }, int(1));
    let b = apply(Expr::Tag { label: "Err".into() }, int(1));
    let program = call2("equal", a, b);
    match run(program).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "False"),
        other => panic!("expected False, got {other}"),
    }
}

#[test]
fn different_types_not_equal() {
    // equal 1 "1" -> False
    let program = call2("equal", int(1), str_lit("1"));
    match run(program).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "False"),
        other => panic!("expected False, got {other}"),
    }
}

#[test]
fn equal_binaries_are_equal() {
    let a = Expr::Binary { value: vec![1, 2, 3] };
    let b = Expr::Binary { value: vec![1, 2, 3] };
    let program = call2("equal", a, b);
    match run(program).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "True"),
        other => panic!("expected True, got {other}"),
    }
}

// ============================================================================
// Additional end-to-end: overwrite existing field, list_pop, int_absolute
// ============================================================================

#[test]
fn overwrite_changes_existing_field() {
    // let r = (+x) 1 {} in (:=x) 99 r
    // Expected: record with x=99
    let build = apply(apply(Expr::Extend { label: "x".into() }, int(1)), Expr::Empty);
    let program = let_in(
        "r",
        build,
        apply(
            apply(Expr::Overwrite { label: "x".into() }, int(99)),
            var("r"),
        ),
    );
    let v = run(program).unwrap();
    match v.as_ref() {
        Value::Record(fields) => {
            assert!(matches!(fields.get("x").unwrap().as_ref(), Value::Integer(99)));
        }
        other => panic!("expected record, got {other}"),
    }
}

#[test]
fn list_pop_returns_head_and_tail() {
    // list_pop (cons 10 (cons 20 []))
    // Expected: Ok({head: 10, tail: [20]})
    let list = apply(
        apply(Expr::Cons, int(10)),
        apply(apply(Expr::Cons, int(20)), Expr::Tail),
    );
    let program = call1("list_pop", list);
    let v = run(program).unwrap();
    match v.as_ref() {
        Value::Tagged { label, value } => {
            assert_eq!(label, "Ok");
            match value.as_ref() {
                Value::Record(fields) => {
                    assert!(matches!(fields.get("head").unwrap().as_ref(), Value::Integer(10)));
                    match fields.get("tail").unwrap().as_ref() {
                        Value::LinkedList(rest) => {
                            assert_eq!(rest.len(), 1);
                            assert!(matches!(rest[0].as_ref(), Value::Integer(20)));
                        }
                        other => panic!("expected list tail, got {other}"),
                    }
                }
                other => panic!("expected record, got {other}"),
            }
        }
        other => panic!("expected Ok, got {other}"),
    }
}

#[test]
fn list_pop_empty_returns_error() {
    let program = call1("list_pop", Expr::Tail);
    match run(program).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "Error"),
        other => panic!("expected Error, got {other}"),
    }
}

#[test]
fn int_absolute_of_negative() {
    let program = call1("int_absolute", int(-7));
    assert!(matches!(run(program).unwrap().as_ref(), Value::Integer(7)));
}

#[test]
fn string_split_returns_head_and_tail() {
    // string_split "a,b,c" ","
    let program = call2("string_split", str_lit("a,b,c"), str_lit(","));
    let v = run(program).unwrap();
    match v.as_ref() {
        Value::Record(fields) => {
            assert!(matches!(fields.get("head").unwrap().as_ref(), Value::Str(s) if s == "a"));
            match fields.get("tail").unwrap().as_ref() {
                Value::LinkedList(items) => assert_eq!(items.len(), 2),
                other => panic!("expected list, got {other}"),
            }
        }
        other => panic!("expected record, got {other}"),
    }
}

#[test]
fn string_split_once_returns_pre_and_post() {
    let program = call2("string_split_once", str_lit("hello-world"), str_lit("-"));
    let v = run(program).unwrap();
    match v.as_ref() {
        Value::Tagged { label, value } => {
            assert_eq!(label, "Ok");
            match value.as_ref() {
                Value::Record(fields) => {
                    assert!(matches!(fields.get("pre").unwrap().as_ref(), Value::Str(s) if s == "hello"));
                    assert!(matches!(fields.get("post").unwrap().as_ref(), Value::Str(s) if s == "world"));
                }
                other => panic!("expected record, got {other}"),
            }
        }
        other => panic!("expected Ok, got {other}"),
    }
}

#[test]
fn string_length_counts_grapheme_clusters() {
    // "café" has 4 graphemes even though é might be multi-byte
    let program = call1("string_length", str_lit("café"));
    assert!(matches!(run(program).unwrap().as_ref(), Value::Integer(4)));
}

#[test]
fn binary_from_integers_creates_correct_bytes() {
    // binary_from_integers (cons 65 (cons 66 []))
    let list = apply(
        apply(Expr::Cons, int(65)),
        apply(apply(Expr::Cons, int(66)), Expr::Tail),
    );
    let program = call1("binary_from_integers", list);
    assert!(matches!(run(program).unwrap().as_ref(), Value::Binary(b) if b == &vec![65, 66]));
}

#[test]
fn int_compare_returns_ordering() {
    // int_compare 1 5 -> Lt
    match run(call2("int_compare", int(1), int(5))).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "Lt"),
        other => panic!("expected Lt, got {other}"),
    }
    // int_compare 5 5 -> Eq
    match run(call2("int_compare", int(5), int(5))).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "Eq"),
        other => panic!("expected Eq, got {other}"),
    }
    // int_compare 5 1 -> Gt
    match run(call2("int_compare", int(5), int(1))).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "Gt"),
        other => panic!("expected Gt, got {other}"),
    }
}

#[test]
fn string_starts_with_and_ends_with() {
    match run(call2("string_starts_with", str_lit("hello"), str_lit("hel"))).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "True"),
        other => panic!("expected True, got {other}"),
    }
    match run(call2("string_ends_with", str_lit("hello"), str_lit("llo"))).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "True"),
        other => panic!("expected True, got {other}"),
    }
}

#[test]
fn string_lowercase_and_uppercase() {
    match run(call1("string_lowercase", str_lit("HELLO"))).unwrap().as_ref() {
        Value::Str(s) => assert_eq!(s, "hello"),
        other => panic!("expected string, got {other}"),
    }
    match run(call1("string_uppercase", str_lit("hello"))).unwrap().as_ref() {
        Value::Str(s) => assert_eq!(s, "HELLO"),
        other => panic!("expected string, got {other}"),
    }
}

#[test]
fn string_from_binary_with_invalid_utf8_returns_error() {
    let bad_bytes = Expr::Binary { value: vec![0xFF, 0xFE] };
    let program = call1("string_from_binary", bad_bytes);
    match run(program).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "Error"),
        other => panic!("expected Error, got {other}"),
    }
}

#[test]
fn int_parse_invalid_string_returns_error() {
    match run(call1("int_parse", str_lit("not_a_number"))).unwrap().as_ref() {
        Value::Tagged { label, .. } => assert_eq!(label, "Error"),
        other => panic!("expected Error, got {other}"),
    }
}
