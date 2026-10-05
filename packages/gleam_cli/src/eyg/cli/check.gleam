import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/cli/internal/config
import eyg/hub/cache
import eyg/ir/tree as ir
import eyg/parser
import filepath
import gleam/list
import loam/execute
import loam/platform/computer
import loam/source
import loam/system
import touch_grass/interface

pub fn execute(
  input: source.Input,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use input <- system.try(source.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))

  let context =
    infer.pure() |> infer.with_effects(interface.types(computer.effects()))
  let state = execute.State(config.client.origin, cache.empty())
  use #(_poly, type_, errors) <- system.then(check_from(
    source,
    cwd,
    context,
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

pub fn check_from(
  source: ir.Node(source.Location),
  cwd: String,
  context: infer.Context,
  state: execute.State,
) -> system.Effect(
  #(binding.Poly, binding.Mono, List(#(source.Location, error.Reason))),
) {
  let #(dir, path) = case source.1.origin {
    source.Disk(path:) -> #(filepath.directory_name(path), path)
    // source without a file resolves imports against the working directory.
    source.Pipe -> #(cwd, "")
    source.Inline -> #(cwd, "")
    source.Repl -> #(cwd, "")
    source.Content(..) -> #(cwd, "")
    source.Release(..) -> #(cwd, "")
  }

  do_check_all(context, dir, source, state, [], [path])
}

fn do_check_all(
  context: infer.Context,
  directory: String,
  source: #(ir.Expression(source.Location), source.Location),
  state: execute.State,
  errors: List(#(source.Location, error.Reason)),
  visited: List(String),
) -> system.Effect(
  #(binding.Poly, binding.Mono, List(#(source.Location, error.Reason))),
) {
  check_loop(
    infer.check(context, source),
    context,
    directory,
    state,
    errors,
    visited,
  )
}

fn check_loop(
  step: infer.Step(infer.Analysis(source.Location)),
  context: infer.Context,
  directory: String,
  state: execute.State,
  errors: List(#(source.Location, error.Reason)),
  visited: List(String),
) -> system.Effect(#(binding.Poly, binding.Mono, _)) {
  case step {
    infer.Done(analysis) ->
      system.Done(#(
        infer.poly_type(analysis),
        infer.type_(analysis),
        list.append(errors, infer.all_errors(analysis)),
      ))
    infer.Lookup(reference:, resume:) -> {
      case reference {
        ir.Content(cid:) -> {
          use #(result, state) <- system.then(execute.lookup_reference(
            cid,
            state,
          ))
          resume(type_from_lookup(result))
          |> check_loop(context, directory, state, errors, visited)
        }
        ir.Package(package:) -> {
          use #(result, state) <- system.then(execute.lookup_package(
            package,
            state,
          ))
          resume(type_from_lookup(result))
          |> check_loop(context, directory, state, errors, visited)
        }
        ir.Version(package:, version:) -> {
          use #(result, state) <- system.then(execute.lookup_version(
            package,
            version,
            state,
          ))
          resume(type_from_lookup(result))
          |> check_loop(context, directory, state, errors, visited)
        }
        ir.Pinned(release:) -> {
          use #(result, state) <- system.then(execute.lookup_pinned(
            release,
            state,
          ))
          resume(type_from_lookup(result))
          |> check_loop(context, directory, state, errors, visited)
        }
        ir.Relative(location:) -> {
          case system.resolve_relative(directory, location) {
            Ok(path) -> {
              case cycle_check(visited, path) {
                Ok(Nil) -> {
                  use code <- system.then(system.read_file(path))
                  case code {
                    Ok(code) ->
                      case source.parse_input(code, source.File(location)) {
                        Ok(dependency) -> {
                          let check =
                            do_check_all(
                              context,
                              filepath.directory_name(path),
                              dependency,
                              state,
                              errors,
                              [path, ..visited],
                            )
                          use #(poly, _type_, errors) <- system.then(check)
                          resume(Ok(poly))
                          |> check_loop(
                            context,
                            directory,
                            state,
                            errors,
                            visited,
                          )
                        }
                        Error(_reason) ->
                          resume(Error(Nil))
                          |> check_loop(
                            context,
                            directory,
                            state,
                            errors,
                            visited,
                          )
                      }
                    Error(_reason) -> {
                      resume(Error(Nil))
                      |> check_loop(context, directory, state, errors, visited)
                    }
                  }
                }
                Error(_cycle) ->
                  resume(Error(Nil))
                  |> check_loop(context, directory, state, errors, visited)
              }
            }
            Error(_reason) ->
              resume(Error(Nil))
              |> check_loop(context, directory, state, errors, visited)
          }
        }
      }
    }
  }
}

fn type_from_lookup(result) {
  case result {
    Ok(cache.Module(type_:, ..)) -> Ok(type_)
    Error(_) -> Error(Nil)
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
