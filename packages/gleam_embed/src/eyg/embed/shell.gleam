//// A shell runs pieces of code one after another, keeping the variables each
//// defines, with their types, for the next. Every piece is parsed and type
//// checked against the host's effects before any of it runs.
////
//// A person typing and an agent calling a tool can share one shell.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/embed/run
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/parser as parser_parser
import gleam/dict
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Positions in the code, as the parser annotates it.
pub type Span =
  #(Int, Int)

/// A module the host can give the shell: its value and its type.
pub type Module {
  Module(value: state.Value(Span), type_: binding.Poly)
}

pub type Effects =
  List(#(String, #(binding.Mono, binding.Mono)))

pub type Shell {
  Shell(
    effects: Effects,
    scope: state.Scope(Span),
    types: List(#(String, binding.Poly)),
    resolve: fn(ir.Reference) -> Result(Module, Nil),
  )
}

pub type Outcome {
  /// The value of the last expression, or none when the code ends in a `let`.
  Returned(Option(state.Value(Span)))
  ParseFailed(String)
  /// Nothing ran.
  TypeFailed(List(String))
  /// Everything before this ran.
  Stopped(String)
}

pub type Run(s) {
  Run(shell: Shell, state: s, outcome: Outcome)
}

/// A shell for programs that can perform these effects, labels with the types
/// lifted out and lowered back.
pub fn new(effects: Effects) -> Shell {
  Shell(effects:, scope: [], types: [], resolve: fn(_) { Error(Nil) })
}

/// Give the shell modules for references, for example from `eyg_hub`'s cache.
pub fn with_references(
  shell: Shell,
  resolve: fn(ir.Reference) -> Result(Module, Nil),
) -> Shell {
  Shell(..shell, resolve:)
}

/// Put a value in scope.
pub fn with_value(shell: Shell, name: String, module: Module) -> Shell {
  let Module(value:, type_:) = module
  Shell(..shell, scope: [#(name, value), ..shell.scope], types: [
    #(name, type_),
    ..shell.types
  ])
}

/// Evaluate the source of a module and put it in scope, for a library of
/// helpers. The module cannot perform effects, its functions can.
pub fn with_module(
  shell: Shell,
  name: String,
  code: String,
) -> Result(Shell, String) {
  use module <- result.map(module(shell, code))
  with_value(shell, name, module)
}

/// Evaluate a pure module with the shell's references.
pub fn module(shell: Shell, code: String) -> Result(Module, String) {
  use source <- result.try(
    parser.all_from_string(code)
    |> result.map_error(parser.format_error(_, code)),
  )
  let analysis = check(infer.pure(), source, shell.resolve)
  case infer.all_errors(analysis) {
    [] -> {
      let pure = fn(_, label, _) { Error("a module cannot perform " <> label) }
      case run.expression(source, [], Nil, pure, values(shell)) {
        #(_, Ok(value)) -> Ok(Module(value:, type_: infer.poly_type(analysis)))
        #(_, Error(failure)) -> Error(run.describe(failure))
      }
    }
    errors -> Error(string.join(describe(errors, code), "\n"))
  }
}

/// A value in scope.
pub fn lookup(shell: Shell, name: String) -> Result(state.Value(Span), Nil) {
  list.key_find(shell.scope, name)
}

/// A string field of a module in scope, such as a library's readme.
pub fn text(shell: Shell, name: String, field: String) -> String {
  case lookup(shell, name) {
    Ok(v.Record(fields)) ->
      case dict.get(fields, field) {
        Ok(v.String(text)) -> text
        _ -> ""
      }
    _ -> ""
  }
}

/// Run code, answering its effects with `handle`.
pub fn run(
  shell: Shell,
  code: String,
  state: s,
  handle: run.Handler(s, Span),
) -> Run(s) {
  case prepare(shell, code) {
    Error(outcome) -> Run(shell, state, outcome)
    Ok(#(source, types)) ->
      run.block(source, shell.scope, state, handle, values(shell))
      |> finish(shell, types)
  }
}

/// `run` with a handler that returns a promise.
pub fn run_async(
  shell: Shell,
  code: String,
  state: s,
  handle: run.AsyncHandler(s, Span),
) -> Promise(Run(s)) {
  case prepare(shell, code) {
    Error(outcome) -> promise.resolve(Run(shell, state, outcome))
    Ok(#(source, types)) ->
      run.block_async(source, shell.scope, state, handle, values(shell))
      |> promise.map(finish(_, shell, types))
  }
}

fn prepare(shell: Shell, code) {
  use source <- result.try(
    parse_block(code)
    |> result.map_error(fn(reason) {
      ParseFailed(parser.format_error(reason, code))
    }),
  )
  let context =
    infer.pure()
    |> infer.with_effects(shell.effects)
    |> infer.with_variables(shell.types)
  let analysis = check(context, source, shell.resolve)
  case errors(analysis) {
    [] -> Ok(#(source, final_scope(analysis)))
    errors -> Error(TypeFailed(describe(errors, code)))
  }
}

fn finish(return, shell: Shell, types) {
  case return {
    #(state, Ok(#(value, scope))) ->
      Run(Shell(..shell, scope:, types:), state, Returned(value))
    #(state, Error(failure)) ->
      Run(shell, state, Stopped(run.describe(failure)))
  }
}

/// What to tell a person, or a model, about a run.
/// `printed` is anything the program printed, oldest first.
pub fn report(printed: List(String), outcome: Outcome) -> String {
  let outcome = case outcome {
    Returned(Some(value)) -> simple_debug.inspect(value)
    Returned(None) -> "{}"
    ParseFailed(reason) -> "The code did not parse.\n" <> reason
    TypeFailed(reasons) ->
      "The code did not type check, nothing ran.\n"
      <> string.join(reasons, "\n")
    Stopped(reason) -> "The program stopped.\n" <> reason
  }
  case printed {
    [] -> outcome
    _ ->
      "Printed:\n" <> string.join(printed, "\n") <> "\nReturned:\n" <> outcome
  }
}

fn values(shell: Shell) -> run.Resolver(Span) {
  fn(reference) {
    shell.resolve(reference) |> result.map(fn(module) { module.value })
  }
}

fn check(context, source, resolve: fn(ir.Reference) -> Result(Module, Nil)) {
  do_check(infer.check(context, source), resolve)
}

fn do_check(step, resolve) {
  case step {
    infer.Done(analysis) -> analysis
    infer.Lookup(reference:, resume:) ->
      resolve(reference)
      |> result.map(fn(module: Module) { module.type_ })
      |> resume
      |> do_check(resolve)
  }
}

/// Code that ends with a `let` has nothing to return. The parser leaves a
/// vacant node there, which is the only error to ignore.
fn errors(analysis: infer.Analysis(Span)) {
  let tail = tail_meta(analysis.original)
  infer.all_errors(analysis)
  |> list.filter(fn(error) { error != #(tail, error.Todo) })
}

fn tail_meta(source: ir.Node(m)) -> m {
  case source {
    #(ir.Let(_, _, then), _) -> tail_meta(then)
    #(_, meta) -> meta
  }
}

/// The type of every variable in scope at the end of the code, each
/// generalised against this analysis so that the next piece can use it.
fn final_scope(analysis: infer.Analysis(Span)) {
  let infer.Analysis(tree:, bindings:, ..) = analysis
  let #(_, #(_, _, _, scope)) = tail(tree)
  use #(name, poly) <- list.map(scope)
  let #(mono, bindings) = binding.instantiate(poly, 1, bindings)
  #(name, binding.gen(binding.resolve(mono, bindings), 0, bindings))
}

fn tail(tree) {
  case tree {
    #(ir.Let(_, _, then), _) -> tail(then)
    other -> other
  }
}

fn describe(errors, code) {
  list.map(errors, fn(error) {
    let #(#(start, _end), reason) = error
    let line = string.slice(code, 0, start) |> string.split("\n") |> list.length
    "line " <> int.to_string(line) <> ": " <> debug.reason(reason)
  })
}

/// Parse code that may end with a `let`, leaving a vacant node in its place.
fn parse_block(code) {
  case parser.block_from_string(code) {
    Ok(#(#(assigns, tail), [])) -> {
      let end = string.length(code)
      // The parser returns lexical order; from_block folds outward from the tail.
      Ok(ir.from_block(
        list.reverse(assigns),
        option.unwrap(tail, #(ir.Vacant, #(end, end))),
      ))
    }
    Ok(#(_, [#(token, at), ..])) ->
      Error(parser_parser.TrailingTokens(token, at))
    Error(reason) -> Error(reason)
  }
}
