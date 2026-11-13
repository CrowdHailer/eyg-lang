//// Run a pinned program, recording every effect in a journal.
////
//// Effects are answered by a handler, the computer harness for `eyg record` or
//// a policy for overlay agents. Every answer is recorded with how it was answered.
//// References resolve through the pin, nothing is read from disk or the hub while running.

import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import filepath
import glasshouse/journal
import glasshouse/lock
import glasshouse/recorder.{type Recorder}
import glasshouse/store
import gleam/dict.{type Dict}
import gleam/option.{type Option, None, Some}
import gleam/result
import loam/execute
import loam/pin
import loam/platform/computer
import loam/source
import loam/system
import multiformats/cid/v1
import touch_grass/harness/computer as harness

pub type Handled {
  /// The program resumes with the reply.
  Answered(reply: execute.Value, answer: journal.Answer, path: Option(String))
  /// The effect is not available or its input was invalid.
  Refused(reason: execute.Reason)
  /// Answering the effect failed, i.e. a policy gate raised an error.
  Failed(debug: execute.Debug)
  /// The program stopped the process.
  Halted(status: Int)
}

/// Answer an effect raised by the program.
pub type Handler(s) =
  fn(String, execute.Value, source.Location, s) -> system.Effect(#(Handled, s))

pub type Outcome(a) {
  Completed(a)
  Raised(execute.Debug)
  Exited(status: Int)
}

type Context(s) {
  Context(loader: Loader, recorder: Recorder, handler: Handler(s), state: s)
}

/// Resolves references through the pin, evaluated modules are kept for reuse.
type Loader {
  Loader(
    pinned: pin.Pinned,
    cwd: String,
    store: store.Store,
    modules: Dict(String, execute.Value),
  )
}

/// Run a block, the scope is returned for shells.
pub fn run_block(
  source: ir.Node(source.Location),
  scope: execute.Scope,
  pinned: pin.Pinned,
  cwd: String,
  recorder: Recorder,
  handler: Handler(s),
  state: s,
) -> system.Effect(
  #(Outcome(#(Option(execute.Value), execute.Scope)), Recorder, s),
) {
  let loader =
    Loader(pinned:, cwd:, store: recorder.store(recorder), modules: dict.new())
  let context = Context(loader:, recorder:, handler:, state:)
  loop(block.execute(source, scope), block.resume, context)
}

/// Run an expression to its value.
pub fn run_expression(
  source: ir.Node(source.Location),
  scope: execute.Scope,
  pinned: pin.Pinned,
  cwd: String,
  recorder: Recorder,
  handler: Handler(s),
  state: s,
) -> system.Effect(#(Outcome(execute.Value), Recorder, s)) {
  let loader =
    Loader(pinned:, cwd:, store: recorder.store(recorder), modules: dict.new())
  let context = Context(loader:, recorder:, handler:, state:)
  loop(expression.execute(source, scope), expression.resume, context)
}

fn loop(
  return: Result(a, execute.Debug),
  resume: fn(execute.Value, execute.Env, execute.Stack) ->
    Result(a, execute.Debug),
  context: Context(s),
) -> system.Effect(#(Outcome(a), Recorder, s)) {
  case return {
    Ok(value) ->
      system.Done(#(Completed(value), context.recorder, context.state))
    Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
      use started <- system.then(system.now())
      use #(handled, state) <- system.then(context.handler(
        label,
        lift,
        meta,
        context.state,
      ))
      use ended <- system.then(system.now())
      let duration = ended - started
      case handled {
        Answered(reply:, answer:, path:) -> {
          let recorder =
            recorder.record(
              context.recorder,
              label,
              lift,
              reply,
              answer,
              path,
              started,
              duration,
            )
          loop(
            resume(reply, env, k),
            resume,
            Context(..context, recorder:, state:),
          )
        }
        Refused(reason:) ->
          system.Done(#(
            Raised(#(reason, meta, env, k)),
            context.recorder,
            state,
          ))
        Failed(debug:) -> system.Done(#(Raised(debug), context.recorder, state))
        Halted(status:) -> {
          let recorder =
            recorder.record(
              context.recorder,
              label,
              lift,
              v.unit(),
              journal.Performed,
              None,
              started,
              duration,
            )
          system.Done(#(Exited(status), recorder, state))
        }
      }
    }
    Error(#(break.UndefinedReference(reference), meta, env, k)) ->
      case load(reference, meta, context.loader) {
        Ok(#(value, loader)) ->
          loop(resume(value, env, k), resume, Context(..context, loader:))
        Error(reason) ->
          system.Done(#(
            Raised(#(reason, meta, env, k)),
            context.recorder,
            context.state,
          ))
      }
    Error(debug) ->
      system.Done(#(Raised(debug), context.recorder, context.state))
  }
}

/// Resolve a reference from the pin, evaluating the module purely.
fn load(reference: ir.Reference, meta: source.Location, loader: Loader) {
  let missing = break.UndefinedReference(reference)
  case reference {
    ir.Relative(location:) -> {
      use path <- result.try(
        import_path(meta.origin, location, loader.cwd)
        |> result.replace_error(missing),
      )
      let key = "file:" <> path
      case dict.get(loader.modules, key) {
        Ok(value) -> Ok(#(value, loader))
        Error(Nil) -> {
          use node <- result.try(
            dict.get(loader.pinned.imports, path)
            |> result.replace_error(missing),
          )
          evaluate(node, key, loader)
        }
      }
    }
    ir.Content(cid:) -> stored(cid, source.Content(cid), loader, missing)
    ir.Pinned(release: ir.Release(package:, version:, module:)) ->
      stored(module, source.Release(package, version, module), loader, missing)
    ir.Package(package:) -> {
      use lock.Release(version:, module:) <- result.try(
        dict.get(loader.pinned.lock.packages, package)
        |> result.replace_error(missing),
      )
      use #(cid, _) <- result.try(
        v1.from_string(module) |> result.replace_error(missing),
      )
      stored(cid, source.Release(package, version, cid), loader, missing)
    }
    ir.Version(package:, version:) -> {
      use module <- result.try(
        dict.get(loader.pinned.lock.versions, #(package, version))
        |> result.replace_error(missing),
      )
      use #(cid, _) <- result.try(
        v1.from_string(module) |> result.replace_error(missing),
      )
      stored(cid, source.Release(package, version, cid), loader, missing)
    }
  }
}

fn stored(cid: v1.Cid, origin: source.Origin, loader: Loader, missing) {
  let key = v1.to_string(cid)
  case dict.get(loader.modules, key) {
    Ok(value) -> Ok(#(value, loader))
    Error(Nil) -> {
      use node <- result.try(
        store.get_node(loader.store, key)
        |> result.replace_error(missing),
      )
      let location = source.Location(origin, source.Json)
      evaluate(ir.map_annotation(node, fn(_) { location }), key, loader)
    }
  }
}

// Imports are pure, any effect is an error.
fn evaluate(node, key, loader: Loader) {
  use #(value, loader) <- result.map(pure(expression.execute(node, []), loader))
  #(value, Loader(..loader, modules: dict.insert(loader.modules, key, value)))
}

fn pure(return, loader: Loader) {
  case return {
    Ok(value) -> Ok(#(value, loader))
    Error(#(break.UndefinedReference(reference), meta, env, k)) -> {
      use #(value, loader) <- result.try(load(reference, meta, loader))
      pure(expression.resume(value, env, k), loader)
    }
    Error(#(reason, _, _, _)) -> Error(reason)
  }
}

/// The absolute path of an import, code without a file imports relative to the working directory.
pub fn import_path(
  origin: source.Origin,
  location: String,
  cwd: String,
) -> Result(String, Nil) {
  case origin {
    source.Disk(path:) ->
      system.resolve_relative(filepath.directory_name(path), location)
      |> result.replace_error(Nil)
    source.Inline | source.Pipe | source.Repl ->
      system.resolve_relative(cwd, location) |> result.replace_error(Nil)
    source.Content(..) | source.Release(..) -> Error(Nil)
  }
}

/// Answer effects with the computer harness, as `eyg run` does.
pub fn computer(
  label: String,
  lift: execute.Value,
  meta: source.Location,
  state: s,
) -> system.Effect(#(Handled, s)) {
  case computer.cast(label, lift) {
    Ok(harness.Exit(status)) -> system.Done(#(Halted(status), state))
    Ok(effect) -> {
      use path <- system.then(effect_path(label, lift, meta.origin))
      use reply <- system.map(computer.extrinsic(effect, meta.origin))
      #(Answered(reply, journal.Performed, path), state)
    }
    Error(reason) -> system.Done(#(Refused(reason), state))
  }
}

/// The absolute path a filesystem effect acts on.
pub fn effect_path(
  label: String,
  lift: execute.Value,
  origin: source.Origin,
) -> system.Effect(Option(String)) {
  case requested_path(label, lift) {
    Some(path) -> {
      use resolved <- system.map(source.resolve_filepath(origin, path))
      option.from_result(resolved)
    }
    None -> system.Done(None)
  }
}

/// The path in the input of a filesystem effect.
pub fn requested_path(label: String, lift: execute.Value) -> Option(String) {
  case label, lift {
    "ReadFile", v.Record(_)
    | "WriteFile", v.Record(_)
    | "AppendFile", v.Record(_)
    | "Clone", v.Record(_)
    | "Commit", v.Record(_)
    | "Mount", v.Record(_)
    -> cast.field("path", cast.as_string, lift) |> option.from_result
    "DeleteFile", v.String(path)
    | "MakeDirectory", v.String(path)
    | "ReadDirectory", v.String(path)
    -> Some(path)
    _, _ -> None
  }
}
