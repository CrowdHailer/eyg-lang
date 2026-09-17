import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/execute
import eyg/cli/internal/source
import eyg/cli/system
import eyg/hub/cache
import eyg/ir/tree as ir
import eyg/parser
import filepath
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import multiformats/cid/v1

type State {
  State(
    client: client.Client,
    packages: cache.Cache(Nil),
    types: dict.Dict(String, binding.Poly),
  )
}

pub fn execute(
  input: source.Input,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use input <- system.try(execute.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))

  let context = infer.unpure()
  let #(dir, path) = case source.1.origin {
    source.Disk(path:) -> #(filepath.directory_name(path), path)
    // source without a file resolves imports against the working directory.
    source.Pipe -> #(cwd, "")
    source.Inline -> #(cwd, "")
    source.Repl -> #(cwd, "")
    source.Content(..) -> #(cwd, "")
    source.Release(..) -> #(cwd, "")
  }

  let state = State(config.client, cache.ready(), dict.new())
  use #(_poly, type_, errors, _state) <- system.then(check_all(
    context,
    Some(dir),
    source,
    [],
    [path],
    state,
  ))

  use Nil <- system.then(
    system.each(
      list.map(errors, fn(error) {
        let #(location, reason) = error
        let message = debug.render_reason(reason)
        let hint = debug.hint(reason)
        parser.render_error(
          message,
          hint,
          source.code(location),
          source.span(location),
        )
        |> system.stdout()
      }),
    ),
  )

  case errors {
    [] -> {
      let type_ = debug.render_type(type_)
      use Nil <- system.then(system.stdout(type_))
      system.Done(Ok(0))
    }
    _ -> {
      Error("")
      |> system.Done
    }
  }
}

fn check_all(
  context: infer.Context,
  directory: Option(String),
  source: #(ir.Expression(source.Location), source.Location),
  errors: List(#(source.Location, error.Reason)),
  visited: List(String),
  state: State,
) -> system.Effect(
  #(binding.Poly, binding.Mono, List(#(source.Location, error.Reason)), State),
) {
  check_loop(
    infer.check(context, source),
    context,
    directory,
    errors,
    visited,
    state,
  )
}

fn check_loop(
  step: infer.Step(infer.Analysis(source.Location)),
  context: infer.Context,
  directory: Option(String),
  errors: List(#(source.Location, error.Reason)),
  visited: List(String),
  state: State,
) -> system.Effect(#(binding.Poly, binding.Mono, _, State)) {
  case step {
    infer.Done(analysis) ->
      system.Done(#(
        infer.poly_type(analysis),
        infer.type_(analysis),
        list.append(errors, infer.all_errors(analysis)),
        state,
      ))
    infer.Lookup(reference:, resume:) -> {
      use #(answer, errors, state) <- system.then(lookup(
        reference,
        context,
        directory,
        errors,
        visited,
        state,
      ))
      check_loop(resume(answer), context, directory, errors, visited, state)
    }
  }
}

fn lookup(reference, context, directory, errors, visited, state) {
  case reference {
    ir.Relative(location:) -> {
      let path = case directory {
        Some(directory) -> execute.resolve_relative(directory, location)
        // A hub module has no filesystem origin for imports.
        None -> Error("no directory for hub module")
      }
      case path {
        Error(_) -> system.Done(#(Error(Nil), errors, state))
        Ok(path) ->
          load_dependency(
            path,
            Some(filepath.directory_name(path)),
            fn() {
              use code <- system.then(source.read_input(source.File(path)))
              system.Done(result.try(code, source.parse(_, source.Disk(path))))
            },
            context,
            errors,
            visited,
            state,
          )
      }
    }
    _ -> {
      use #(resolved, state) <- system.then(resolve(reference, state))
      case resolved {
        Error(_) -> system.Done(#(Error(Nil), errors, state))
        Ok(cid) ->
          load_dependency(
            "#" <> v1.to_string(cid),
            None,
            fn() {
              use fetched <- system.then(client.get_module(cid, state.client))
              system.Done(
                result.map(fetched, fn(tree) {
                  ir.map_annotation(tree, fn(_) {
                    source.Location(source.Content(cid), source.Json)
                  })
                }),
              )
            },
            context,
            errors,
            visited,
            state,
          )
      }
    }
  }
}

// Cache inferred types, not evaluated module values: checking must neither run
// module initializers nor skip errors in code that evaluation would not reach.
fn load_dependency(
  key,
  directory,
  load,
  context,
  errors,
  visited,
  state: State,
) {
  case dict.get(state.types, key), cycle_check(visited, key) {
    Ok(poly), _ -> system.Done(#(Ok(poly), errors, state))
    _, Error(_) -> system.Done(#(Error(Nil), errors, state))
    Error(_), Ok(_) -> {
      use dependency <- system.then(load())
      case dependency {
        Error(_) -> system.Done(#(Error(Nil), errors, state))
        Ok(dependency) -> {
          use #(poly, _type_, errors, state) <- system.then(check_all(
            context,
            directory,
            dependency,
            errors,
            [key, ..visited],
            state,
          ))
          let state = State(..state, types: dict.insert(state.types, key, poly))
          system.Done(#(Ok(poly), errors, state))
        }
      }
    }
  }
}

fn resolve(reference, state) {
  case reference {
    ir.Content(cid) -> system.Done(#(Ok(cid), state))
    _ -> {
      use state <- system.then(pull_packages(state))
      let resolved = case state.packages.cursor_status {
        cache.Pulled ->
          case reference {
            ir.Package(package) ->
              cache.package(state.packages, package)
              |> result.map(fn(entry) { entry.module })
            ir.Version(package, version) ->
              cache.unbound_release(state.packages, package, version)
            ir.Pinned(release) ->
              case cache.release(state.packages, release) {
                cache.Available(cid) -> Ok(cid)
                _ -> Error(Nil)
              }
            _ -> Error(Nil)
          }
        _ -> Error(Nil)
      }
      system.Done(#(resolved, state))
    }
  }
}

fn pull_packages(state: State) {
  case state.packages.cursor_status {
    cache.ReadyToPull -> {
      // Only release metadata goes through the evaluation cache. Sources are
      // fetched separately and inferred by check_all, including transitive deps.
      use packages <- system.then(
        client.run_all_with(
          state.packages,
          state.client.origin,
          fn(request) { system.Fetch(request, _) },
          fn(algorithm, bytes) { system.Hash(algorithm, bytes, _) },
          fn(duration) { system.Wait(duration, _) },
        )(system.Done),
      )
      system.Done(State(..state, packages:))
    }
    _ -> system.Done(state)
  }
}

pub fn cycle_check(visited, path) {
  do_cycle_check(visited, path, [])
}

fn do_cycle_check(visited, path, acc) {
  case visited {
    [] -> Ok(Nil)
    [parent, ..] if parent == path -> Error([path, ..acc])
    [parent, ..rest] -> do_cycle_check(rest, path, [parent, ..acc])
  }
}
