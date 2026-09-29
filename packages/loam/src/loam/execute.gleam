//// Evaluate EYG with the computer harness and resolve imports through Loam effects.

import eyg/hub/cache.{type Cache}
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser/location
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import loam/platform/computer
import loam/source
import loam/system
import multiformats/cid/v1
import ogre/origin

pub type Value =
  state.Value(source.Location)

pub type Scope =
  state.Scope(source.Location)

pub type Env =
  state.Env(source.Location)

pub type Stack =
  state.Stack(source.Location)

pub type Reason =
  state.Reason(source.Location)

pub type Debug =
  state.Debug(source.Location)

pub type State {
  State(origin: origin.Origin, cache: Cache(source.Location))
}

pub fn block(source, scope, state) {
  loop(block.execute(source, scope), state)
}

fn try_await(
  result: system.Effect(Result(t, Reason)),
  meta: source.Location,
  env: Env,
  k: Stack,
  then: fn(t) -> system.Effect(Result(r, Debug)),
) -> system.Effect(Result(r, Debug)) {
  use result <- system.then(result)
  case result {
    Ok(value) -> then(value)
    Error(reason) -> system.Done(Error(#(reason, meta, env, k)))
  }
}

pub fn loop(
  return: Result(#(Option(Value), Scope), Debug),
  state: State,
) -> system.Effect(Result(#(Option(Value), Scope), Debug)) {
  case return {
    Ok(return) -> system.Done(Ok(return))
    Error(#(reason, meta, env, k)) ->
      case reason {
        break.UnhandledEffect(label, lift) ->
          case computer.cast(label, lift) {
            Ok(effect) -> {
              use value <- system.then(computer.extrinsic(effect, meta.origin))
              loop(block.resume(value, env, k), state)
            }

            Error(reason) -> system.Done(Error(#(reason, meta, env, k)))
          }
        break.UndefinedReference(reference) -> {
          use value <- try_await(
            lookup(reference, meta.origin, state),
            meta,
            env,
            k,
          )
          loop(block.resume(value, env, k), state)
        }

        _ -> system.Done(Error(#(reason, meta, env, k)))
      }
  }
}

fn update(state: State) -> system.Effect(State) {
  let #(cache, effects) = cache.flush(state.cache)
  case effects {
    [] -> system.Done(State(..state, cache:))
    _ -> {
      use applicable <- system.then(
        system.traverse(effects, do_effect(_, state)),
      )
      let cache = list.fold(applicable, cache, apply)
      update(State(..state, cache:))
    }
  }
}

fn do_effect(
  action: cache.Action,
  state: State,
) -> system.Effect(cache.ActionCompleted) {
  cache.compute(
    action,
    state.origin,
    fn(request) { system.Fetch(request, _) },
    fn(algorithm, bytes) { system.Hash(algorithm, bytes, _) },
  )(system.Done)
}

fn apply(
  cache: Cache(source.Location),
  update: cache.ActionCompleted,
) -> Cache(source.Location) {
  case update {
    cache.FetchModuleCompleted(cid, _) -> {
      let #(cache, _done) =
        cache.update(cache, update, fn(_) {
          source.Location(source.Content(cid), source.Json)
        })
      cache
    }
    cache.PullPackagesCompleted(result) -> {
      let #(cache, _done) = cache.pull_packages_completed(cache, result)
      cache
    }
  }
}

fn lookup(
  reference: ir.Reference,
  origin,
  state: State,
) -> system.Effect(Result(Value, Reason)) {
  case reference {
    ir.Content(cid) -> lookup_reference(cid, state)
    ir.Package(package) -> lookup_package(package, state)
    ir.Version(package, version) -> lookup_version(package, version, state)
    ir.Pinned(release) -> lookup_pinned(release, state)
    ir.Relative(location:) -> lookup_relative(location, origin, state)
  }
}

fn lookup_reference(
  cid: v1.Cid,
  state: State,
) -> system.Effect(Result(Value, Reason)) {
  // A pulled release does not fetch its module, so ask for the one being read.
  let cache = cache.fetch(state.cache, cid)
  use state <- system.map(update(State(..state, cache:)))
  case cache.module(state.cache, cid) {
    cache.Available(cache.Module(value:, ..)) -> Ok(value)
    cache.Unavailable(reason) -> Error(reason)
    cache.Unknown -> {
      // The module itself may have been fetched successfully; this branch
      // also fires when one of its dependencies couldn't be resolved. We
      // can't yet say *which* dep is missing, but we can keep the user
      // from chasing the wrong CID.
      abort(
        "failed to load module #"
        <> v1.to_string(cid)
        <> " (the module itself or one of its dependencies could not be fetched from "
        <> "$EYG_ORIGIN)",
      )
      |> Error()
    }
  }
}

fn lookup_package(
  package: String,
  state: State,
) -> system.Effect(Result(Value, Reason)) {
  let cache = cache.pull(state.cache)
  use state <- system.then(update(State(..state, cache:)))
  case cache.package(state.cache, package) {
    Ok(cache.Entry(module:, ..)) -> lookup_reference(module, state)
    Error(Nil) -> {
      abort("package not found: @" <> package)
      |> Error
      |> system.Done
    }
  }
}

fn lookup_version(
  package: String,
  version: Int,
  state: State,
) -> system.Effect(Result(Value, Reason)) {
  let cache = cache.pull(state.cache)
  use state <- system.then(update(State(..state, cache:)))
  case cache.unbound_release(state.cache, package, version) {
    Ok(module) -> lookup_reference(module, state)
    Error(Nil) ->
      abort("package not found: @" <> package <> ":" <> int.to_string(version))
      |> Error
      |> system.Done
  }
}

fn lookup_pinned(
  release: ir.Release,
  state: State,
) -> system.Effect(Result(Value, Reason)) {
  let cache = cache.pull(state.cache)
  use state <- system.then(update(State(..state, cache:)))

  case cache.release(state.cache, release) {
    cache.Available(resolved) -> lookup_reference(resolved, state)
    cache.Unknown -> {
      abort("module not found for package: @" <> release.package)
      |> Error
      |> system.Done
    }
    cache.Unavailable(Nil) ->
      break.UndefinedReference(ir.Pinned(release:))
      |> Error
      |> system.Done
  }
}

// used to handle cases where the runtime aborts the program
fn abort(reason: String) -> break.Reason(m, c) {
  break.UnhandledEffect("Abort", v.String(reason))
}

fn lookup_relative(
  location: String,
  origin: source.Origin,
  state: State,
) -> system.Effect(Result(Value, Reason)) {
  use resolved <- system.then(source.resolve_filepath(origin, location))

  case resolved {
    Ok(path) -> {
      use code <- system.then(system.read_file(path))
      case code {
        Ok(code) ->
          case source.parse(code, source.Disk(path:)) {
            Ok(source) -> {
              use result <- system.then(pure_loop(
                expression.execute(source, []),
                state,
              ))
              case result {
                Ok(value) -> system.Done(Ok(value))
                Error(#(reason, _, _, _)) -> system.Done(Error(reason))
              }
            }
            Error(_) ->
              abort("failed to read parse source from location: " <> location)
              |> Error
              |> system.Done
          }
        Error(_reason) ->
          abort("failed to read module from location: " <> location)
          |> Error
          |> system.Done
      }
    }
    Error(_) ->
      system.Done(Error(break.UndefinedReference(ir.Relative(location:))))
  }
}

pub fn pure_loop(
  return: Result(Value, Debug),
  state: State,
) -> system.Effect(Result(Value, Debug)) {
  case return {
    Ok(return) -> system.Done(Ok(return))
    Error(#(reason, meta, env, k)) ->
      case reason {
        break.UndefinedReference(reference) -> {
          use value <- try_await(
            lookup(reference, meta.origin, state),
            meta,
            env,
            k,
          )
          pure_loop(expression.resume(value, env, k), state)
        }
        _ -> system.Done(Error(#(reason, meta, env, k)))
      }
  }
}

/// One frame of the runtime stack trace - the failing expression's
/// meta (with `arg: None`) plus every closure call recorded by a
/// Trace frame on the continuation stack (with `arg: Some(value)`).
pub type Frame {
  Frame(location: source.Location, arg: Option(Value))
}

/// Render a runtime error as a stack trace.
///
/// Collects the failing expression's meta plus every `Trace` frame on
/// the continuation stack and renders one line per frame innermost
/// first. The deepest frame whose origin is a user-code origin (i.e.
/// not `Content` or `Release`) is marked with `→` and shown with a
/// source snippet + caret; other frames are summarised as
/// `in <label>:<line> (<arg value>)`.
pub fn render_error(
  reason: Reason,
  location: source.Location,
  stack: Stack,
  cwd: String,
) -> String {
  let frames = [Frame(location, None), ..collect_traces(stack, [])]
  let description = simple_debug.describe(reason)
  let hint = simple_debug.hint(reason)
  let header = ["error: " <> description, "hint: " <> hint]
  let focus = find_focus(frames, 0)
  // echo focus
  // let frames = list.drop(frames, focus |> option.unwrap(0))
  // let frames = list.take(frames, 3)
  // echo "here"
  let trace_lines = render_frames(frames, focus, 0, cwd, [])
  case trace_lines {
    [] -> string.join(header, "\n")
    _ -> string.join(list.append(header, ["", ..trace_lines]), "\n")
  }
}

fn collect_traces(stack: Stack, acc: List(Frame)) -> List(Frame) {
  case stack {
    state.Empty -> list.reverse(acc)
    state.Stack(state.Trace(arg), meta, rest) ->
      collect_traces(rest, [Frame(meta, Some(arg)), ..acc])
    state.Stack(_, _, rest) -> collect_traces(rest, acc)
  }
}

/// Index of the deepest frame written by the user (i.e. backed by a
/// file, the REPL, inline code, or stdin).
fn find_focus(frames: List(Frame), i: Int) -> Option(Int) {
  case frames {
    [] -> None
    [Frame(source.Location(origin, _), _), ..rest] ->
      case origin {
        source.Content(_) | source.Release(..) -> find_focus(rest, i + 1)
        _ -> Some(i)
      }
  }
}

fn render_frames(
  frames: List(Frame),
  focus: Option(Int),
  i: Int,
  cwd: String,
  acc: List(String),
) -> List(String) {
  case frames {
    [] -> list.reverse(acc)
    [frame, ..rest] -> {
      let is_focus = focus == Some(i)
      let lines = render_frame(frame, is_focus, cwd)
      render_frames(
        rest,
        focus,
        i + 1,
        cwd,
        list.fold(lines, acc, fn(acc, line) { [line, ..acc] }),
      )
    }
  }
}

fn render_frame(frame: Frame, is_focus: Bool, cwd: String) -> List(String) {
  let Frame(source.Location(origin, source), arg) = frame
  let label = origin_label(origin, cwd)
  let prefix = case is_focus {
    True -> "→ in "
    False -> "  in "
  }
  let suffix = case arg {
    Some(value) -> " (" <> simple_debug.inspect(value) <> ")"
    None -> ""
  }
  case source {
    source.Text(code:, span:) -> {
      let #(start, _) = span
      let line_no = line_at(code, start)
      let header = case line_no {
        0 -> prefix <> label <> suffix
        n -> prefix <> label <> ":" <> int.to_string(n) <> suffix
      }
      case is_focus {
        True -> [header, ..location.source_context(code, span)]
        False -> [header]
      }
    }
    source.Json ->
      case is_focus {
        True -> [prefix <> label <> " (no source)" <> suffix]
        False -> [prefix <> label <> suffix]
      }
  }
}

fn origin_label(origin: source.Origin, cwd: String) -> String {
  case origin {
    source.Disk(path:) -> string.replace(path, cwd <> "/", "")
    source.Pipe -> "<pipe>"
    source.Inline -> "<inline>"
    source.Repl -> "<repl>"
    source.Content(cid:) -> "#" <> v1.to_string(cid)
    source.Release(package:, version:, cid: _) ->
      "@" <> package <> ":" <> int.to_string(version)
  }
}

/// 1-based line number for a byte offset into `code`. Returns 0 when
/// `code` is empty.
fn line_at(code: String, offset: Int) -> Int {
  case code {
    "" -> 0
    _ -> string.slice(code, 0, offset) |> string.split("\n") |> list.length
  }
}
