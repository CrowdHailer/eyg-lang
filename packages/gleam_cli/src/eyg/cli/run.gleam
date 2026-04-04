import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/parser.{describe_reason} as _
import filepath
import gleam/fetchx
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile
import touch_grass/decode_json
import touch_grass/fetch
import touch_grass/read

pub fn execute(file) {
  use code <- promisex.try_sync(
    simplifile.read(file) |> result.map_error(simplifile.describe_error),
  )
  use source <- promisex.try_sync(
    parser.all_from_string(code) |> result.map_error(describe_reason),
  )
  let source = ir.clear_annotation(source)

  use cwd <- promisex.try_sync(
    simplifile.current_directory()
    |> result.map_error(simplifile.describe_error),
  )
  use path <- promisex.try_sync(resolve_relative(cwd, file))
  let dir = filepath.directory_name(path)
  use result <- promise.map(loop(block.execute(source, []), dir))
  result
  |> result.map_error(simple_debug.describe)
}

fn loop(return, cwd) {
  case return {
    Ok(#(Some(value), _)) -> promise.resolve(Ok(simple_debug.inspect(value)))
    Ok(#(None, _)) -> promise.resolve(Ok(""))
    Error(#(reason, _meta, env, k)) ->
      case reason {
        break.UnhandledEffect("DecodeJSON", lift) -> {
          use encoded <- promisex.try_sync(decode_json.decode(lift))
          loop(block.resume(decode_json.sync(encoded), env, k), cwd)
        }
        break.UnhandledEffect("Fetch", lift) -> {
          use request <- promisex.try_sync(fetch.decode(lift))
          use result <- promise.await(fetchx.send_bits(request))
          let result = result.map_error(result, string.inspect)
          loop(block.resume(fetch.encode(result), env, k), cwd)
        }
        break.UnhandledEffect("Read", lift) -> {
          use path <- promisex.try_sync(read.decode(lift))
          let result = simplifile.read_bits(path)
          let result = result.map_error(result, string.inspect)
          loop(block.resume(read.encode(result), env, k), cwd)
        }
        break.UndefinedRelease(package:, release:, module:) -> {
          use value <- promise.try_await(lookup_release(
            package,
            release,
            module,
            cwd,
          ))
          loop(block.resume(value, env, k), cwd)
        }
        _ -> promise.resolve(Error(reason))
      }
  }
}

fn lookup_release(package, release, module, cwd) {
  case package {
    "./" <> _ | "/" <> _ | "../" <> _ -> {
      case resolve_relative(cwd, package) {
        Ok(path) -> {
          let code = case simplifile.read(path) {
            Ok(code) -> code
            Error(reason) -> {
              io.println(simplifile.describe_error(reason) <> " " <> path)
              panic
            }
          }
          let source = case parser.all_from_string(code) {
            Ok(source) -> source
            Error(reason) -> {
              io.println(describe_reason(reason))
              panic
            }
          }
          let source = ir.clear_annotation(source)
          pure_loop(
            expression.execute(source, []),
            filepath.directory_name(path),
          )
        }
        Error(_) ->
          promise.resolve(
            Error(break.UndefinedRelease(package:, release:, module:)),
          )
      }
    }
    _ ->
      promise.resolve(
        Error(break.UndefinedRelease(package:, release:, module:)),
      )
  }
}

fn pure_loop(return, cwd) {
  case return {
    Ok(value) -> promise.resolve(Ok(value))
    Error(#(reason, _meta, env, k)) ->
      case reason {
        break.UndefinedRelease(package:, release:, module:) -> {
          use result <- promise.await(lookup_release(
            package,
            release,
            module,
            cwd,
          ))
          case result {
            Ok(value) -> pure_loop(expression.resume(value, env, k), cwd)
            Error(reason) -> promise.resolve(Error(reason))
          }
        }
        _ -> promise.resolve(Error(reason))
      }
  }
}

fn resolve_relative(root, relative) {
  let joined = case filepath.is_absolute(relative) {
    True -> relative
    False -> filepath.join(root, relative)
  }

  filepath.expand(joined) |> result.replace_error("invalid relative directory")
}
