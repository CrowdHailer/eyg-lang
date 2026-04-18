import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/midas_bun
import eyg/cli/internal/source
import eyg/hub/publisher
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/value
import eyg/ir/tree as ir
import filepath
import gleam/fetchx
import gleam/http/request
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result.{try}
import gleam/string
import multiformats/cid/v1
import ogre/operation
import ogre/origin
import simplifile
import snag
import spotless
import spotless/oauth_2_1/token
import spotless/proof_key_for_code_exchange as pkce
import touch_grass/decode_json
import touch_grass/fetch
import touch_grass/file_system/append_file
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file
import touch_grass/http
import untethered/ledger/schema

pub fn block(source, scope, dir, config: config.Config) {
  loop(block.execute(source, scope), dir, config.client)
}

pub fn pure(source: ir.Node(t), dir, config: client.Client) {
  pure_loop(expression.execute(source, []), dir, config)
}

fn loop(return, cwd, config: client.Client) -> promise.Promise(Result(_, _)) {
  case return {
    Ok(return) -> promise.resolve(Ok(return))
    Error(#(reason, _meta, env, k)) ->
      case reason {
        break.UnhandledEffect("AppendFile", lift) -> {
          use input <- promisex.try_sync(append_file.decode(lift))
          let output = append_file(cwd, input)
          loop(block.resume(append_file.encode(output), env, k), cwd, config)
        }
        break.UnhandledEffect("DecodeJSON", lift) -> {
          use encoded <- promisex.try_sync(decode_json.decode(lift))
          loop(block.resume(decode_json.sync(encoded), env, k), cwd, config)
        }
        break.UnhandledEffect("DNSimple", lift) -> {
          use result <- promise.try_await(service_fetch("dnsimple", lift, 8080))
          loop(block.resume(fetch.encode(result), env, k), cwd, config)
        }
        break.UnhandledEffect("Fetch", lift) -> {
          use request <- promisex.try_sync(fetch.decode(lift))
          use result <- promise.await(fetchx.send_bits(request))
          let result = result.map_error(result, string.inspect)
          loop(block.resume(fetch.encode(result), env, k), cwd, config)
        }
        break.UnhandledEffect("GitHub", lift) -> {
          use result <- promise.try_await(service_fetch("github", lift, 8080))
          loop(block.resume(fetch.encode(result), env, k), cwd, config)
        }
        break.UnhandledEffect("Netlify", lift) -> {
          use result <- promise.try_await(service_fetch("netlify", lift, 8080))
          loop(block.resume(fetch.encode(result), env, k), cwd, config)
        }
        break.UnhandledEffect("Print", lift) -> {
          use message <- promisex.try_sync(cast.as_string(lift))
          io.print(message)
          loop(block.resume(value.unit(), env, k), cwd, config)
        }
        break.UnhandledEffect("ReadDirectory", lift) -> {
          use input <- promisex.try_sync(read_directory.decode(lift))
          let output = read_directory(cwd, input)
          loop(block.resume(read_directory.encode(output), env, k), cwd, config)
        }
        break.UnhandledEffect("ReadFile", lift) -> {
          use input <- promisex.try_sync(read_file.decode(lift))
          let output = read_file(cwd, input)
          loop(block.resume(read_file.encode(output), env, k), cwd, config)
        }
        break.UnhandledEffect("Vimeo", lift) -> {
          use result <- promise.try_await(service_fetch("vimeo", lift, 8080))
          loop(block.resume(fetch.encode(result), env, k), cwd, config)
        }
        break.UnhandledEffect("WriteFile", lift) -> {
          use input <- promisex.try_sync(write_file.decode(lift))
          let output = write_file(cwd, input)
          loop(block.resume(write_file.encode(output), env, k), cwd, config)
        }
        break.UndefinedReference(cid) -> {
          use value <- promise.try_await(lookup_reference(cid, cwd, config))
          loop(block.resume(value, env, k), cwd, config)
        }
        break.UndefinedRelease(package:, release:, module:) -> {
          use value <- promise.try_await(lookup_release(
            package,
            release,
            module,
            cwd,
            config,
          ))
          loop(block.resume(value, env, k), cwd, config)
        }
        _ -> promise.resolve(Error(reason))
      }
  }
}

fn lookup_reference(
  cid,
  cwd,
  config,
) -> promise.Promise(Result(value.Value(_, _), _)) {
  use result <- promise.await(client.get_module(cid, config))
  case result {
    Ok(Some(source)) -> {
      use value <- promise.try_await(pure(source, cwd, config))
      promise.resolve(Ok(value))
    }
    Ok(None) -> {
      io.println("no module for #" <> v1.to_string(cid))
      panic
    }
    Error(_) -> {
      io.println("failed to fetch #" <> v1.to_string(cid))
      panic
    }
  }
}

fn lookup_release(package, release, module, cwd, config) {
  case package, release {
    "./" <> _, 0 | "/" <> _, 0 | "../" <> _, 0 -> {
      case resolve_relative(cwd, package) {
        Ok(path) -> {
          let source = case source.read(path) {
            Ok(source) -> source
            Error(reason) -> {
              io.println(reason <> " " <> path)
              panic
            }
          }

          pure_loop(
            expression.execute(source, []),
            filepath.directory_name(path),
            config,
          )
        }
        Error(_) ->
          promise.resolve(
            Error(break.UndefinedRelease(package:, release:, module:)),
          )
      }
    }
    _, 0 -> {
      use response <- promise.await(client.pull_package(config, package))
      let assert Ok(response) = response
      case list.reverse(response.entries) {
        [] ->
          promise.resolve(
            Error(break.UndefinedRelease(package:, release:, module:)),
          )
        [schema.ArchivedEntry(payload:, ..), ..] -> {
          let assert Ok(entry) = json.parse(payload, publisher.decoder())
          let cid = entry.content.module
          use value <- promise.try_await(lookup_reference(cid, cwd, config))
          promise.resolve(Ok(value))
        }
      }
    }
    _, _ ->
      promise.resolve(
        Error(break.UndefinedRelease(package:, release:, module:)),
      )
  }
}

fn pure_loop(return, cwd, config) {
  case return {
    Ok(value) -> promise.resolve(Ok(value))
    Error(#(reason, _meta, env, k)) ->
      case reason {
        break.UndefinedReference(cid) -> {
          use value <- promise.try_await(lookup_reference(cid, cwd, config))
          pure_loop(expression.resume(value, env, k), cwd, config)
        }
        break.UndefinedRelease(package:, release:, module:) -> {
          use result <- promise.await(lookup_release(
            package,
            release,
            module,
            cwd,
            config,
          ))
          case result {
            Ok(value) ->
              pure_loop(expression.resume(value, env, k), cwd, config)
            Error(reason) -> promise.resolve(Error(reason))
          }
        }
        _ -> promise.resolve(Error(reason))
      }
  }
}

pub fn resolve_relative(root, relative) {
  let joined = case filepath.is_absolute(relative) {
    True -> relative
    False -> filepath.join(root, relative)
  }

  filepath.expand(joined) |> result.replace_error("invalid relative directory")
}

pub fn append_file(cwd, input: append_file.Input) {
  {
    let append_file.Input(path:, contents:) = input
    use path <- try(
      resolve_relative(cwd, path) |> result.replace_error(simplifile.Enoent),
    )
    simplifile.append_bits(path, contents)
  }
  |> result.map_error(simplifile.describe_error)
}

pub fn read_directory(
  cwd cwd: String,
  path path: String,
) -> read_directory.Output {
  {
    use path <- try(
      resolve_relative(cwd, path) |> result.replace_error(simplifile.Enoent),
    )
    use children <- try(simplifile.read_directory(path))
    let children =
      list.filter_map(children, fn(child) {
        let path = path <> "/" <> child

        use info <- try(simplifile.file_info(path))
        case simplifile.file_info_type(info) {
          simplifile.File -> Ok(#(child, read_directory.File(size: info.size)))
          simplifile.Directory -> Ok(#(child, read_directory.Directory))
          simplifile.Symlink -> Error(simplifile.Unknown(""))
          simplifile.Other -> Error(simplifile.Unknown(""))
        }
      })
    Ok(children)
  }
  |> result.map_error(simplifile.describe_error)
}

@external(javascript, "./execute_ffi.mjs", "readAtOffset")
fn read_at_offset(
  path path: String,
  offset offset: Int,
  limit limit: Int,
) -> Result(BitArray, simplifile.FileError)

pub fn read_file(cwd, input: read_file.Input) {
  {
    let read_file.Input(path:, limit:, offset:) = input
    use path <- try(
      resolve_relative(cwd, path) |> result.replace_error(simplifile.Enoent),
    )

    read_at_offset(path:, limit:, offset:)
  }
  |> result.map_error(simplifile.describe_error)
}

pub fn write_file(cwd, input: write_file.Input) {
  {
    let write_file.Input(path:, contents:) = input
    use path <- try(
      resolve_relative(cwd, path) |> result.replace_error(simplifile.Enoent),
    )
    simplifile.write_bits(path, contents)
  }
  |> result.map_error(simplifile.describe_error)
}

fn service_fetch(service, lift, port) {
  use operation <- promisex.try_sync(http.operation_to_gleam(lift))
  use result <- promise.await(
    midas_bun.run(spotless.authenticate(service, [], "", port, pkce.S256)),
  )
  use result <- promise.await(case result {
    Ok(token.Response(access_token:, ..)) -> {
      let request = service_request(service, operation, access_token)
      use result <- promise.map(fetchx.send_bits(request))
      result.map_error(result, string.inspect)
    }
    Error(reason) -> promise.resolve(Error(snag.line_print(reason)))
  })
  promise.resolve(Ok(result))
}

fn service_request(service, operation, token) {
  let origin = case service {
    "dnsimple" -> origin.https("api.dnsimple.com")
    "github" -> origin.https("api.github.com")
    "netlify" -> origin.https("api.netlify.com")
    "tavily" -> origin.https("api.tavily.com")
    "vimeo" -> origin.https("api.vimeo.com")
    _ -> panic
  }
  operation.to_request(operation, origin)
  |> request.set_header("authorization", "Bearer " <> token)
}
