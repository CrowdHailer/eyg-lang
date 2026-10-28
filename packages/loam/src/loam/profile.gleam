//// An instrumented evaluation runner. Ordinary execution uses loam/execute.
//// Every callable application gets a span, including curried stages and callbacks.
//// Continuation capture/resume closes/reopens frame segments to preserve a tree.

import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import loam/execute
import loam/platform/computer
import loam/source
import loam/system

type Frame {
  Frame(id: Int, name: String, attributes: List(#(String, String)))
}

type Profile {
  Profile(
    next_id: Int,
    frames: Dict(Int, Frame),
    active: List(Frame),
    names: Dict(source.Location, String),
    sources: List(source.Origin),
    pure: Bool,
  )
}

pub fn block(node: ir.Node(source.Location), scope, runtime) {
  use #(result, runtime, _) <- system.map(
    system.span(
      "eyg.profile",
      [#("eyg.profile", "true"), #("eyg.source", origin(node.1.origin))],
      fn() {
        let profile = Profile(0, dict.new(), [], dict.new(), [], False)
        loop(
          state.E(node),
          builtin.default(scope),
          state.Empty,
          runtime,
          profile,
        )
      },
      fn(output) {
        case output.0 {
          Ok(_) -> None
          Error(#(reason, _, _, _)) -> Some(simple_debug.describe(reason))
        }
      },
    ),
  )
  #(result, runtime)
}

fn loop(control, env: execute.Env, stack, runtime, profile: Profile) {
  let wanted = stack_frames(stack, profile.frames, [])
  let #(closing, opening) = changed(profile.active, wanted)
  case closing, opening {
    [], [] -> advance(control, env, stack, runtime, profile)
    _, _ -> {
      use Nil <- system.then(synchronize(closing, opening))
      advance(control, env, stack, runtime, Profile(..profile, active: wanted))
    }
  }
}

fn advance(control, env: execute.Env, stack, runtime, profile: Profile) {
  case control, stack {
    state.E(#(ir.Vacant, _)), state.Empty ->
      system.Done(#(Ok(#(None, env.scope)), runtime, profile))
    state.Call(callable, arg, meta), _ -> {
      let profile = discover(callable, profile)
      let #(name, kind, location) = describe(callable, meta, profile.names)
      let id = profile.next_id
      let frame =
        Frame(id, name, [
          #("eyg.profile.kind", kind),
          #("eyg.profile.call_id", int.to_string(id)),
          #("code.function.name", name),
          #("code.file.path", origin(location.origin)),
          #("code.line.number", int.to_string(line(location))),
        ])
      let profile =
        Profile(
          ..profile,
          next_id: id + 1,
          frames: dict.insert(profile.frames, id, frame),
          active: list.append(profile.active, [frame]),
        )
      use Nil <- system.then(system.SpanStart(
        name,
        frame.attributes,
        system.Done,
      ))
      step(
        state.Call(callable, arg, meta),
        env,
        state.Stack(state.ProfileReturn(id, env), meta, stack),
        runtime,
        profile,
      )
    }
    _, _ -> step(control, env, stack, runtime, profile)
  }
}

fn step(control, env: execute.Env, stack, runtime, profile: Profile) {
  case state.step(control, env, stack) {
    state.Loop(control, env, stack) ->
      loop(control, env, stack, runtime, profile)
    state.Break(Ok(value)) -> {
      use Nil <- system.then(close(profile.active, None))
      system.Done(#(
        Ok(#(Some(value), env.scope)),
        runtime,
        Profile(..profile, active: []),
      ))
    }
    state.Break(Error(#(reason, meta, env, stack))) ->
      case reason {
        break.UnhandledEffect(_, _) if profile.pure ->
          fail(reason, meta, env, stack, runtime, profile)
        break.UnhandledEffect(label, input) ->
          case computer.cast(label, input) {
            Ok(effect) -> {
              use value <- system.then(execute.traced_effect(
                label,
                effect,
                meta.origin,
              ))
              loop(state.V(value), env, stack, runtime, profile)
            }
            Error(reason) -> fail(reason, meta, env, stack, runtime, profile)
          }
        break.UndefinedReference(reference) -> {
          let active = profile.active
          let pure = profile.pure
          use #(result, runtime, profile) <- system.then(
            system.span(
              "eyg.import",
              [#("eyg.profile.kind", "import")],
              fn() { lookup(reference, meta, runtime, profile) },
              fn(output) {
                case output.0 {
                  Ok(_) -> None
                  Error(reason) -> Some(simple_debug.describe(reason))
                }
              },
            ),
          )
          let profile = Profile(..profile, active:, pure:)
          case result {
            Ok(value) -> loop(state.V(value), env, stack, runtime, profile)
            Error(reason) -> fail(reason, meta, env, stack, runtime, profile)
          }
        }
        _ -> fail(reason, meta, env, stack, runtime, profile)
      }
  }
}

fn fail(reason, meta, env, stack, runtime, profile: Profile) {
  use Nil <- system.then(close(
    profile.active,
    Some(simple_debug.describe(reason)),
  ))
  system.Done(#(
    Error(#(reason, meta, env, stack)),
    runtime,
    Profile(..profile, active: []),
  ))
}

// Local imports use this runner too, while retaining ordinary import purity.
// Hub cache materialization is shared with execute; calls into its returned
// closures are still observed by this runner.
fn lookup(reference, meta: source.Location, runtime, profile: Profile) {
  case reference {
    ir.Relative(path) -> {
      use loaded <- system.then(load(path, meta.origin))
      case loaded {
        Error(message) ->
          system.Done(#(
            Error(break.UnhandledEffect("Abort", v.String(message))),
            runtime,
            profile,
          ))
        Ok(node) -> {
          use #(result, runtime, profile) <- system.map(loop(
            state.E(node),
            builtin.default([]),
            state.Empty,
            runtime,
            Profile(..profile, active: [], pure: True),
          ))
          let result = case result {
            Ok(#(Some(value), _)) -> Ok(value)
            Ok(#(None, _)) -> Error(break.Vacant)
            Error(#(reason, _, _, _)) -> Error(reason)
          }
          #(result, runtime, profile)
        }
      }
    }
    _ -> {
      use #(result, runtime) <- system.map(execute.lookup(
        reference,
        meta.origin,
        runtime,
      ))
      #(result, runtime, profile)
    }
  }
}

fn load(path, origin) {
  use path <- system.then(source.resolve_filepath(origin, path))
  use path <- system.try(path)
  use code <- system.then(system.read_file(path))
  use code <- system.try(code)
  system.Done(source.parse(code, source.Disk(path)))
}

fn close(frames, error) {
  use _ <- system.map(
    system.traverse(list.reverse(frames), fn(_) {
      system.SpanEnd(error, system.Done)
    }),
  )
  Nil
}

fn synchronize(closing: List(Frame), opening: List(Frame)) {
  use Nil <- system.then(close(closing, None))
  use _ <- system.map(
    system.traverse(opening, fn(frame) {
      system.SpanStart(
        frame.name,
        [#("eyg.profile.resumed", "true"), ..frame.attributes],
        system.Done,
      )
    }),
  )
  Nil
}

// Compare the outermost-first stacks. Resumed continuations may re-enter frames
// which have already returned; they get new spans with the same logical call ID.
fn changed(active: List(Frame), wanted: List(Frame)) {
  case active, wanted {
    [a, ..active], [b, ..wanted] if a.id == b.id -> changed(active, wanted)
    _, _ -> #(active, wanted)
  }
}

fn stack_frames(stack, frames, acc) {
  case stack {
    state.Empty -> acc
    state.Stack(state.ProfileReturn(id, _), _, rest) -> {
      let assert Ok(frame) = dict.get(frames, id)
      stack_frames(rest, frames, [frame, ..acc])
    }
    state.Stack(_, _, rest) -> stack_frames(rest, frames, acc)
  }
}

fn discover(callable: execute.Value, profile: Profile) {
  case callable {
    v.Closure(_, body, _) -> {
      let meta = body.1
      case list.contains(profile.sources, meta.origin), meta.source {
        False, source.Text(code, _) -> {
          let names = case source.parse(code, meta.origin) {
            Ok(node) -> collect_names(node, None, profile.names)
            Error(_) -> profile.names
          }
          Profile(..profile, names:, sources: [meta.origin, ..profile.sources])
        }
        _, _ -> profile
      }
    }
    _ -> profile
  }
}

fn collect_names(node: ir.Node(source.Location), hint, names) {
  case node.0 {
    ir.Let(label, definition, body) -> {
      let names = collect_names(definition, Some(label), names)
      collect_names(body, None, names)
    }
    ir.Lambda(_, body) -> {
      let names = case hint {
        Some(name) -> dict.insert(names, body.1, name)
        None -> names
      }
      let hint = case body.0 {
        ir.Lambda(..) -> hint
        _ -> None
      }
      collect_names(body, hint, names)
    }
    ir.Apply(#(ir.Builtin("fix"), _), builder) ->
      collect_names(builder, hint, names)
    ir.Apply(f, arg) -> {
      let names = collect_names(f, None, names)
      collect_names(arg, None, names)
    }
    _ -> names
  }
}

fn describe(callable, meta, names) {
  case callable {
    v.Closure(_, body, _) -> {
      let name =
        dict.get(names, body.1)
        |> result.unwrap("<lambda:" <> int.to_string(line(body.1)) <> ">")
      #(name, "function", body.1)
    }
    v.Partial(switch, _) -> {
      let name = case switch {
        v.Builtin(name) -> "!" <> name
        v.Perform(name) -> "perform " <> name
        v.Handle(name) -> "handle " <> name
        v.Resume(_) -> "<resume>"
        v.Select(name) -> "." <> name
        v.Tag(name) -> name
        v.Match(name) -> "match " <> name
        v.NoCases -> "<no cases>"
        v.Cons -> "<cons>"
        v.Extend(name) -> "{ " <> name <> " }"
        v.Overwrite(name) -> "{ " <> name <> " = }"
      }
      #(name, "intrinsic", meta)
    }
    _ -> #("<invalid call>", "intrinsic", meta)
  }
}

fn line(meta: source.Location) {
  case meta.source {
    source.Text(code, #(start, _)) ->
      string.slice(code, 0, start) |> string.split("\n") |> list.length
    source.Json -> 0
  }
}

fn origin(origin) {
  case origin {
    source.Disk(path) -> path
    source.Inline -> "<inline>"
    source.Pipe -> "<stdin>"
    source.Repl -> "<repl>"
    source.Content(cid) -> ir.reference_to_string(ir.Content(cid))
    source.Release(package, version, _) ->
      "@" <> package <> ":" <> int.to_string(version)
  }
}
