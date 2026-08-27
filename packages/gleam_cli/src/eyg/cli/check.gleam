import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/cli/internal/config
import eyg/cli/internal/execute
import eyg/cli/internal/source
import eyg/cli/system
import eyg/ir/tree as ir
import eyg/parser
import filepath
import gleam/list

pub fn execute(
  input: source.Input,
  _config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use code <- system.then(source.read_input_effect(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))

  let context = infer.unpure()
  let path = case source.1.origin {
    source.Disk(path:) -> path
    // empty path results in resolution against current working directory.
    source.Pipe -> ""
    source.Inline -> ""
    source.Repl -> ""
    source.Content(..) -> ""
    source.Release(..) -> ""
  }
  let dir = filepath.directory_name(path)

  use #(_poly, type_, errors) <- system.then(
    check_all(context, dir, source, [], [path]),
  )

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
  directory: String,
  source: #(ir.Expression(source.Location), source.Location),
  errors: List(#(source.Location, error.Reason)),
  visited: List(String),
) -> system.Effect(
  #(binding.Poly, binding.Mono, List(#(source.Location, error.Reason))),
) {
  check_loop(infer.check(context, source), context, directory, errors, visited)
}

fn check_loop(
  step: infer.Step(infer.Analysis(source.Location)),
  context: infer.Context,
  directory: String,
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
        ir.Content(cid: _) ->
          resume(Error(Nil))
          |> check_loop(context, directory, errors, visited)
        ir.Package(package: _) ->
          resume(Error(Nil))
          |> check_loop(context, directory, errors, visited)
        ir.Version(package: _, version: _) ->
          resume(Error(Nil))
          |> check_loop(context, directory, errors, visited)
        ir.Pinned(release: _) ->
          resume(Error(Nil))
          |> check_loop(context, directory, errors, visited)
        ir.Relative(location:) -> {
          case execute.resolve_relative(directory, location) {
            Ok(path) -> {
              case cycle_check(visited, path) {
                Ok(Nil) -> {
                  use code <- system.then(system.read_file(path))
                  case code {
                    Ok(code) ->
                      case source.parse_input(code, source.File(location)) {
                        Ok(dependency) -> {
                          let check =
                            check_all(
                              context,
                              filepath.directory_name(path),
                              dependency,
                              errors,
                              [path, ..visited],
                            )
                          use #(poly, _type_, errors) <- system.then(check)
                          resume(Ok(poly))
                          |> check_loop(context, directory, errors, visited)
                        }
                        Error(_reason) ->
                          resume(Error(Nil))
                          |> check_loop(context, directory, errors, visited)
                      }
                    Error(_reason) -> {
                      resume(Error(Nil))
                      |> check_loop(context, directory, errors, visited)
                    }
                  }
                }
                Error(_cycle) ->
                  resume(Error(Nil))
                  |> check_loop(context, directory, errors, visited)
              }
            }
            Error(_reason) ->
              resume(Error(Nil))
              |> check_loop(context, directory, errors, visited)
          }
        }
      }
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
