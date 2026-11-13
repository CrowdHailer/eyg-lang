//// Run a program to its end in a host.
////
//// The host answers each effect with a handler, and each reference with a
//// resolver, and threads its own state through both. The program is not
//// checked here, see `eyg/embed/shell` for checking before running.

import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option}

pub type Value(m) =
  state.Value(m)

/// Answer an effect, given its label and the value lifted out of the program.
/// An `Error` stops the program with that reason.
pub type Handler(s, m) =
  fn(s, String, Value(m)) -> Result(#(s, Value(m)), String)

/// The same for an effect that takes time.
pub type AsyncHandler(s, m) =
  fn(s, String, Value(m)) -> Promise(Result(#(s, Value(m)), String))

/// The value of a module a program refers to, if the host has it.
pub type Resolver(m) =
  fn(ir.Reference) -> Result(Value(m), Nil)

/// Why a program stopped early.
pub type Failure(m) {
  /// The handler refused an effect.
  Refused(label: String, reason: String)
  /// The interpreter could not continue, a well typed program only stops
  /// here for a reference the resolver does not have.
  Crashed(reason: state.Reason(m))
}

pub fn describe(failure: Failure(m)) -> String {
  case failure {
    Refused(label:, reason:) -> label <> " failed: " <> reason
    Crashed(reason:) -> simple_debug.describe(reason)
  }
}

/// Resolve no references.
pub fn no_references(_reference: ir.Reference) -> Result(Value(m), Nil) {
  Error(Nil)
}

/// Run an expression with the variables in `scope`.
pub fn expression(
  source: ir.Node(m),
  scope: state.Scope(m),
  state: s,
  handle: Handler(s, m),
  resolve: Resolver(m),
) -> #(s, Result(Value(m), Failure(m))) {
  loop(
    expression.execute(source, scope),
    state,
    handle,
    resolve,
    expression.resume,
  )
}

/// Run a block, which may end in a `let` and so have no value, and return the
/// variables in scope at its end as well.
pub fn block(
  source: ir.Node(m),
  scope: state.Scope(m),
  state: s,
  handle: Handler(s, m),
  resolve: Resolver(m),
) -> #(s, Result(#(Option(Value(m)), state.Scope(m)), Failure(m))) {
  loop(block.execute(source, scope), state, handle, resolve, block.resume)
}

fn loop(return, state, handle: Handler(s, m), resolve: Resolver(m), resume) {
  case return {
    Ok(value) -> #(state, Ok(value))
    Error(#(break.UnhandledEffect(label, lift), _meta, env, k)) ->
      case handle(state, label, lift) {
        Ok(#(state, reply)) ->
          loop(resume(reply, env, k), state, handle, resolve, resume)
        Error(reason) -> #(state, Error(Refused(label, reason)))
      }
    Error(#(break.UndefinedReference(reference) as reason, _meta, env, k)) ->
      case resolve(reference) {
        Ok(value) -> loop(resume(value, env, k), state, handle, resolve, resume)
        Error(Nil) -> #(state, Error(Crashed(reason)))
      }
    Error(#(reason, _meta, _env, _k)) -> #(state, Error(Crashed(reason)))
  }
}

/// `expression` for a handler that returns a promise.
pub fn expression_async(
  source: ir.Node(m),
  scope: state.Scope(m),
  state: s,
  handle: AsyncHandler(s, m),
  resolve: Resolver(m),
) -> Promise(#(s, Result(Value(m), Failure(m)))) {
  loop_async(
    expression.execute(source, scope),
    state,
    handle,
    resolve,
    expression.resume,
  )
}

/// `block` for a handler that returns a promise.
pub fn block_async(
  source: ir.Node(m),
  scope: state.Scope(m),
  state: s,
  handle: AsyncHandler(s, m),
  resolve: Resolver(m),
) -> Promise(#(s, Result(#(Option(Value(m)), state.Scope(m)), Failure(m)))) {
  loop_async(block.execute(source, scope), state, handle, resolve, block.resume)
}

fn loop_async(return, state, handle: AsyncHandler(s, m), resolve, resume) {
  case return {
    Ok(value) -> promise.resolve(#(state, Ok(value)))
    Error(#(break.UnhandledEffect(label, lift), _meta, env, k)) -> {
      use reply <- promise.await(handle(state, label, lift))
      case reply {
        Ok(#(state, reply)) ->
          loop_async(resume(reply, env, k), state, handle, resolve, resume)
        Error(reason) ->
          promise.resolve(#(state, Error(Refused(label, reason))))
      }
    }
    Error(#(break.UndefinedReference(reference) as reason, _meta, env, k)) ->
      case resolve(reference) {
        Ok(value) ->
          loop_async(resume(value, env, k), state, handle, resolve, resume)
        Error(Nil) -> promise.resolve(#(state, Error(Crashed(reason))))
      }
    Error(#(reason, _meta, _env, _k)) ->
      promise.resolve(#(state, Error(Crashed(reason))))
  }
}
