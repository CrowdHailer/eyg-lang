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
import gleam/option.{None}
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
      list.map(errors, fn(error) { render_error(error) |> system.stdout() }),
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

  let step = infer.check(context, source)
  // The host's expected result applies to the entry expression, not its imports.
  let dependency_context = infer.Context(..context, expected_type: None)
  check_loop(step, dependency_context, dir, state, [], [path])
}

pub fn render_error(error) {
  let #(location, reason) = error
  parser.render_error(
    debug.render_reason(reason),
    debug.hint(reason),
    source.code(location),
    source.span(location),
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
      use #(type_, state, errors) <- system.then(case reference {
        ir.Content(cid:) ->
          execute.take_type(execute.lookup_reference(cid, state), errors)
        ir.Package(package:) ->
          execute.take_type(execute.lookup_package(package, state), errors)
        ir.Version(package:, version:) ->
          execute.take_type(
            execute.lookup_version(package, version, state),
            errors,
          )
        ir.Pinned(release:) ->
          execute.take_type(execute.lookup_pinned(release, state), errors)
        ir.Relative(location:) ->
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
                            check_loop(
                              infer.check(context, dependency),
                              context,
                              filepath.directory_name(path),
                              state,
                              errors,
                              [path, ..visited],
                            )
                          use #(poly, _type_, errors) <- system.map(check)
                          #(Ok(poly), state, errors)
                        }
                        Error(_reason) ->
                          system.Done(#(Error(Nil), state, errors))
                      }
                    Error(_reason) -> system.Done(#(Error(Nil), state, errors))
                  }
                }
                Error(_cycle) -> system.Done(#(Error(Nil), state, errors))
              }
            }
            Error(_reason) -> system.Done(#(Error(Nil), state, errors))
          }
      })
      type_
      |> resume()
      |> check_loop(context, directory, state, errors, visited)
    }
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
