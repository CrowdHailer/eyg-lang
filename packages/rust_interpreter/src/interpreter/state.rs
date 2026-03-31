// Control / Stack / stepper
// Mirrors packages/gleam_interpreter/src/eyg/interpreter/state.gleam

use super::break_reason::BreakReason;
use super::value::{Scope, Switch, Value};
use crate::ir::ast::Node;
use im;
use std::rc::Rc;

/// Control represents what we're currently evaluating.
#[derive(Debug, Clone)]
pub enum Control {
    /// Evaluating an expression
    Expr(Node),
    /// We have a value
    Val(Rc<Value>),
}

/// Kontinue represents a continuation frame.
#[derive(Debug, Clone)]
pub enum Kontinue {
    /// Evaluate the argument next
    Arg(Node, Env),
    /// Apply the function to the argument
    Apply(Rc<Value>, Env),
    /// Assign the value to a variable and continue
    Assign(String, Node, Env),
    /// Call the function with this argument
    CallWith(Rc<Value>, Env),
    /// Delimited continuation for effect handling
    Delimit {
        label: String,
        handler: Rc<Value>,
        env: Env,
        shallow: bool,
    },
}

/// Stack represents the continuation stack.
#[derive(Debug, Clone)]
pub enum Stack {
    /// A frame with a continuation
    Frame(Kontinue, (), Box<Stack>),
    /// Empty stack with extrinsic effect handlers
    Empty(im::HashMap<String, Extrinsic>),
}

/// Extrinsic effect handler function type
pub type Extrinsic = fn(Rc<Value>) -> Result<Value, BreakReason>;

/// Environment holds variable bindings, references, and builtins.
/// Uses persistent data structures (im::Vector, im::HashMap) for O(log n) cloning.
#[derive(Debug, Clone)]
pub struct Env {
    pub scope: Scope,
    pub references: im::HashMap<String, Rc<Value>>,
    pub builtins: im::HashMap<String, Builtin>,
}

/// Type alias for builtin function implementations
pub type BuiltinFn1 = fn(&Rc<Value>, (), Env, Stack) -> StepReturn;
pub type BuiltinFn2 = fn(&Rc<Value>, &Rc<Value>, (), Env, Stack) -> StepReturn;
pub type BuiltinFn3 = fn(&Rc<Value>, &Rc<Value>, &Rc<Value>, (), Env, Stack) -> StepReturn;
pub type BuiltinFn4 = fn(&Rc<Value>, &Rc<Value>, &Rc<Value>, &Rc<Value>, (), Env, Stack) -> StepReturn;

/// Built-in function with different arities.
#[derive(Clone)]
pub enum Builtin {
    Arity1(BuiltinFn1),
    Arity2(BuiltinFn2),
    Arity3(BuiltinFn3),
    Arity4(BuiltinFn4),
}

impl std::fmt::Debug for Builtin {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Builtin::Arity1(_) => write!(f, "Builtin::Arity1(...)"),
            Builtin::Arity2(_) => write!(f, "Builtin::Arity2(...)"),
            Builtin::Arity3(_) => write!(f, "Builtin::Arity3(...)"),
            Builtin::Arity4(_) => write!(f, "Builtin::Arity4(...)"),
        }
    }
}

/// Next step in the evaluation.
#[derive(Debug)]
pub enum Next {
    /// Continue looping (Stack is boxed to reduce enum size)
    Loop(Control, Env, Box<Stack>),
    /// Break with a result
    Break(EvalResult),
}

/// Debug information for errors (boxed to reduce size).
pub type Debug = Box<(BreakReason, (), Env, Stack)>;

/// Result of evaluation.
pub type EvalResult = Result<Rc<Value>, Debug>;

/// Return type for step functions - includes full context on error for resumption
pub type StepReturn = Result<(Control, Env, Stack), Debug>;

/// Main stepper function - drives the evaluation loop.
/// Box<Stack> is necessary for the recursive Stack type, not for performance.
#[allow(clippy::boxed_local)]
pub fn step(c: Control, env: Env, k: Box<Stack>) -> Next {
    match (c, *k) {
        (Control::Expr(exp), k) => try_step(eval(&exp, env, k)),
        (Control::Val(value), Stack::Empty(_)) => Next::Break(Ok(value)),
        (Control::Val(value), Stack::Frame(k, meta, rest)) => {
            try_step(apply(value, env, k, meta, *rest))
        }
    }
}

/// Helper to convert StepReturn to Next
fn try_step(result: StepReturn) -> Next {
    match result {
        Ok((c, e, k)) => Next::Loop(c, e, Box::new(k)),
        Err(debug) => Next::Break(Err(debug)),
    }
}

impl Env {
    /// Create an empty environment
    pub fn empty() -> Self {
        Env {
            scope: im::Vector::new(),
            references: im::HashMap::new(),
            builtins: im::HashMap::new(),
        }
    }

    /// Extend the scope with a new binding.
    /// Uses im::Vector::push_front for O(log n) structural sharing.
    pub fn extend(&self, label: String, value: Rc<Value>) -> Self {
        let mut new_scope = self.scope.clone();
        new_scope.push_front((label, value));
        Env {
            scope: new_scope,
            references: self.references.clone(),
            builtins: self.builtins.clone(),
        }
    }

    /// Look up a variable in the scope
    pub fn lookup(&self, name: &str) -> Option<Rc<Value>> {
        self.scope
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.clone())
    }
}

/// Helper to wrap a BreakReason with full context
fn wrap_error(reason: BreakReason, env: &Env, k: &Stack) -> Debug {
    Box::new((reason, (), env.clone(), k.clone()))
}

/// Evaluate an expression node
pub fn eval(node: &Node, env: Env, k: Stack) -> StepReturn {
    use crate::ir::ast::Expr;

    let Node(exp, _meta) = node;

    // Helper to return a value directly
    let value = |v: Value| -> StepReturn { Ok((Control::Val(Rc::new(v)), env.clone(), k.clone())) };

    match exp {
        Expr::Lambda { label, body } => {
            let closure = Value::Closure {
                param: label.clone(),
                body: body.clone(),
                env: env.scope.clone(),
            };
            value(closure)
        }

        Expr::Apply { func, argument } => {
            Ok((
                Control::Expr(*func.clone()),
                env.clone(),
                Stack::Frame(Kontinue::Arg(*argument.clone(), env), (), Box::new(k)),
            ))
        }

        Expr::Variable { label } => match env.lookup(label) {
            Some(term) => Ok((Control::Val(term), env.clone(), k.clone())),
            None => Err(wrap_error(BreakReason::UndefinedVariable(label.clone()), &env, &k)),
        },

        Expr::Let { label, definition, body } => {
            Ok((
                Control::Expr(*definition.clone()),
                env.clone(),
                Stack::Frame(
                    Kontinue::Assign(label.clone(), *body.clone(), env),
                    (),
                    Box::new(k),
                ),
            ))
        }

        Expr::Binary { value: data } => value(Value::Binary(data.clone())),
        Expr::Integer { value: data } => value(Value::Integer(*data)),
        Expr::String { value: data } => value(Value::Str(data.clone())),
        Expr::Tail => value(Value::LinkedList(vec![])),
        Expr::Cons => value(Value::Partial(Switch::Cons, vec![])),
        Expr::Vacant => Err(wrap_error(BreakReason::Vacant, &env, &k)),
        Expr::Select { label } => value(Value::Partial(Switch::Select(label.clone()), vec![])),
        Expr::Tag { label } => value(Value::Partial(Switch::Tag(label.clone()), vec![])),
        Expr::Perform { label } => value(Value::Partial(Switch::Perform(label.clone()), vec![])),
        Expr::Empty => value(super::value::unit()),
        Expr::Extend { label } => value(Value::Partial(Switch::Extend(label.clone()), vec![])),
        Expr::Overwrite { label } => value(Value::Partial(Switch::Overwrite(label.clone()), vec![])),
        Expr::Case { label } => value(Value::Partial(Switch::Match(label.clone()), vec![])),
        Expr::NoCases => value(Value::Partial(Switch::NoCases, vec![])),
        Expr::Handle { label } => value(Value::Partial(Switch::Handle(label.clone()), vec![])),

        Expr::Builtin { identifier } => {
            if env.builtins.contains_key(identifier) {
                value(Value::Partial(Switch::Builtin(identifier.clone()), vec![]))
            } else {
                Err(wrap_error(BreakReason::UndefinedBuiltin(identifier.clone()), &env, &k))
            }
        }

        Expr::Reference { identifier } => match env.references.get(identifier) {
            Some(v) => Ok((Control::Val(v.clone()), env, k)),
            None => Err(wrap_error(BreakReason::UndefinedReference(identifier.clone()), &env, &k)),
        },

        Expr::Release { package, release, identifier } => {
            Err(wrap_error(BreakReason::UndefinedRelease {
                package: package.clone(),
                release: *release,
                cid: identifier.clone(),
            }, &env, &k))
        }
    }
}

/// Apply a continuation to a value
pub fn apply(value: Rc<Value>, env: Env, k: Kontinue, _meta: (), rest: Stack) -> StepReturn {
    match k {
        Kontinue::Assign(label, then, env) => {
            let new_env = env.extend(label, value);
            Ok((Control::Expr(then), new_env, rest))
        }

        Kontinue::Arg(arg, env) => {
            Ok((
                Control::Expr(arg),
                env.clone(),
                Stack::Frame(Kontinue::Apply(value, env), (), Box::new(rest)),
            ))
        }

        Kontinue::Apply(f, env) => call(f, value, (), env, rest),

        Kontinue::CallWith(arg, env) => call(value, arg, (), env, rest),

        Kontinue::Delimit { .. } => Ok((Control::Val(value), env, rest)),
    }
}

/// Call a function with an argument
pub fn call(f: Rc<Value>, arg: Rc<Value>, meta: (), env: Env, k: Stack) -> StepReturn {
    use super::cast;

    match f.as_ref() {
        Value::Closure { param, body, env: captured } => {
            let mut new_scope = captured.clone();
            new_scope.push_front((param.clone(), arg));
            let new_env = Env {
                scope: new_scope,
                references: env.references.clone(),
                builtins: env.builtins.clone(),
            };
            Ok((Control::Expr(*body.clone()), new_env, k))
        }

        Value::Partial(switch, applied) => {
            match (switch, applied.as_slice()) {
                (Switch::Cons, [item]) => {
                    let elements = cast::as_list(arg.as_ref()).map_err(|r| wrap_error(r, &env, &k))?;
                    let mut new_list = vec![item.clone()];
                    new_list.extend(elements.iter().cloned());
                    Ok((Control::Val(Rc::new(Value::LinkedList(new_list))), env, k))
                }

                (Switch::Extend(label), [value]) => {
                    let fields = cast::as_record(arg.as_ref()).map_err(|r| wrap_error(r, &env, &k))?;
                    let mut new_fields = fields.clone();
                    new_fields.insert(label.clone(), value.clone());
                    Ok((Control::Val(Rc::new(Value::Record(new_fields))), env, k))
                }

                (Switch::Overwrite(label), [value]) => {
                    let fields = cast::as_record(arg.as_ref()).map_err(|r| wrap_error(r, &env, &k))?;
                    if !fields.contains_key(label) {
                        return Err(wrap_error(BreakReason::MissingField(label.clone()), &env, &k));
                    }
                    let mut new_fields = fields.clone();
                    new_fields.insert(label.clone(), value.clone());
                    Ok((Control::Val(Rc::new(Value::Record(new_fields))), env, k))
                }

                (Switch::Select(label), []) => {
                    let fields = cast::as_record(arg.as_ref()).map_err(|r| wrap_error(r, &env, &k))?;
                    match fields.get(label) {
                        Some(value) => Ok((Control::Val(value.clone()), env, k)),
                        None => Err(wrap_error(BreakReason::MissingField(label.clone()), &env, &k)),
                    }
                }

                (Switch::Tag(label), []) => {
                    Ok((
                        Control::Val(Rc::new(Value::Tagged {
                            label: label.clone(),
                            value: arg,
                        })),
                        env,
                        k,
                    ))
                }

                (Switch::Match(label), [branch, otherwise]) => {
                    let (l, inner) = cast::as_tagged(arg.as_ref()).map_err(|r| wrap_error(r, &env, &k))?;
                    if l == label {
                        call(branch.clone(), inner.clone(), meta, env, k)
                    } else {
                        call(otherwise.clone(), arg, meta, env, k)
                    }
                }

                (Switch::NoCases, []) => Err(wrap_error(BreakReason::NoMatch(Box::new((*arg).clone())), &env, &k)),

                (Switch::Perform(label), []) => perform(label.clone(), arg, env, k),

                (Switch::Handle(label), [handler]) => {
                    deep(label.clone(), handler.clone(), arg, meta, env, k)
                }

                (Switch::Resume(context), []) => {
                    let (popped, resume_env) = context.clone();
                    Ok((Control::Val(arg), resume_env, move_frames(popped, k)))
                }

                (Switch::Builtin(key), _) => {
                    let mut new_applied = applied.clone();
                    new_applied.push(arg);
                    call_builtin(key.clone(), new_applied, meta, env, k)
                }

                _ => {
                    // Partial application - add the argument
                    let mut new_applied = applied.clone();
                    new_applied.push(arg);
                    Ok((
                        Control::Val(Rc::new(Value::Partial(switch.clone(), new_applied))),
                        env,
                        k,
                    ))
                }
            }
        }

        term => Err(wrap_error(BreakReason::NotAFunction(Box::new(term.clone())), &env, &k)),
    }
}

/// Call a built-in function
fn call_builtin(
    key: String,
    applied: Vec<Rc<Value>>,
    meta: (),
    env: Env,
    k: Stack,
) -> StepReturn {
    match env.builtins.get(&key) {
        Some(func) => match (func, applied.as_slice()) {
            (Builtin::Arity1(impl_fn), [x]) => impl_fn(x, meta, env, k),
            (Builtin::Arity2(impl_fn), [x, y]) => impl_fn(x, y, meta, env, k),
            (Builtin::Arity3(impl_fn), [x, y, z]) => {
                impl_fn(x, y, z, meta, env, k)
            }
            (Builtin::Arity4(impl_fn), [x, y, z, a]) => {
                impl_fn(x, y, z, a, meta, env, k)
            }
            _ => {
                // Partial application
                Ok((
                    Control::Val(Rc::new(Value::Partial(Switch::Builtin(key), applied))),
                    env,
                    k,
                ))
            }
        },
        None => Err(wrap_error(BreakReason::UndefinedBuiltin(key), &env, &k)),
    }
}

/// Move frames from a list onto a stack
fn move_frames(frames: Vec<(Kontinue, ())>, mut acc: Stack) -> Stack {
    for (step, meta) in frames.into_iter().rev() {
        acc = Stack::Frame(step, meta, Box::new(acc));
    }
    acc
}

/// Perform an effect
pub fn perform(label: String, arg: Rc<Value>, i_env: Env, k: Stack) -> StepReturn {
    do_perform(label, arg, i_env, k, vec![])
}

/// Helper for perform that accumulates popped frames
fn do_perform(
    label: String,
    arg: Rc<Value>,
    i_env: Env,
    k: Stack,
    mut acc: Vec<(Kontinue, ())>,
) -> StepReturn {
    match k {
        Stack::Frame(
            Kontinue::Delimit {
                label: l,
                handler: h,
                env: e,
                shallow,
            },
            meta,
            rest,
        ) if l == label => {
            // Found matching handler
            if !shallow {
                acc.push((
                    Kontinue::Delimit {
                        label: label.clone(),
                        handler: h.clone(),
                        env: e.clone(),
                        shallow: false,
                    },
                    meta,
                ));
            }

            let resume = Rc::new(Value::Partial(Switch::Resume((acc, i_env.clone())), vec![]));
            let k = Stack::Frame(
                Kontinue::CallWith(arg, e.clone()),
                meta,
                Box::new(Stack::Frame(
                    Kontinue::CallWith(resume, e.clone()),
                    meta,
                    rest,
                )),
            );
            Ok((Control::Val(h), e, k))
        }

        Stack::Frame(kontinue, meta, rest) => {
            acc.push((kontinue, meta));
            do_perform(label, arg, i_env, *rest, acc)
        }

        Stack::Empty(extrinsic) => {
            // Reconstruct the original stack before handling the effect
            let original_k = move_frames(acc, Stack::Empty(extrinsic.clone()));

            // Check for extrinsic handler
            match extrinsic.get(&label) {
                Some(handler) => match handler(arg.clone()) {
                    Ok(term) => {
                        Ok((Control::Val(Rc::new(term)), i_env.clone(), original_k.clone()))
                    }
                    Err(reason) => Err(wrap_error(reason, &i_env, &original_k)),
                },
                None => {
                    // For UnhandledEffect, preserve the stack for resumption
                    Err(wrap_error(
                        BreakReason::UnhandledEffect(label, Box::new((*arg).clone())),
                        &i_env,
                        &original_k
                    ))
                }
            }
        }
    }
}

/// Deep handler - install a delimited continuation
pub fn deep(
    label: String,
    handle: Rc<Value>,
    exec: Rc<Value>,
    meta: (),
    env: Env,
    k: Stack,
) -> StepReturn {
    let k = Stack::Frame(
        Kontinue::Delimit {
            label,
            handler: handle,
            env: env.clone(),
            shallow: false,
        },
        meta,
        Box::new(k),
    );
    call(exec, Rc::new(super::value::unit()), meta, env, k)
}
