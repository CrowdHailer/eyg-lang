import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/midas_bun
import eyg/cli/internal/source
import eyg/hub/publisher
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/value
import filepath
import gleam/fetchx
import gleam/http/request
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
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
import touch_grass/http
import touch_grass/read
import untethered/ledger/schema

pub fn execute(
  file: String,
  config: config.Config,
) -> promise.Promise(Result(String, String)) {
  use source <- promisex.try_sync(source.read(file))

  use cwd <- promisex.try_sync(
    simplifile.current_directory()
    |> result.map_error(simplifile.describe_error),
  )
  use path <- promisex.try_sync(resolve_relative(cwd, file))
  let dir = filepath.directory_name(path)
  use result <- promise.map(loop(block.execute(source, []), dir, config.client))
  result
  |> result.map_error(simple_debug.describe)
}

fn loop(
  return,
  cwd,
  config: client.Client,
) -> promise.Promise(Result(String, _)) {
  case return {
    Ok(#(Some(value), _)) -> promise.resolve(Ok(simple_debug.inspect(value)))
    Ok(#(None, _)) -> promise.resolve(Ok(""))
    Error(#(reason, _meta, env, k)) ->
      case reason {
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
        break.UnhandledEffect("Read", lift) -> {
          use path <- promisex.try_sync(read.decode(lift))
          let result = simplifile.read_bits(path)
          let result = result.map_error(result, string.inspect)
          loop(block.resume(read.encode(result), env, k), cwd, config)
        }
        break.UnhandledEffect("Netlify", lift) -> {
          use result <- promise.try_await(service_fetch("netlify", lift, 8080))
          loop(block.resume(fetch.encode(result), env, k), cwd, config)
        }
        break.UnhandledEffect("Vimeo", lift) -> {
          use result <- promise.try_await(service_fetch("vimeo", lift, 8080))
          loop(block.resume(fetch.encode(result), env, k), cwd, config)
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
      use value <- promise.try_await(pure_loop(
        expression.execute(source, []),
        cwd,
        config,
      ))
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

fn resolve_relative(root, relative) {
  let joined = case filepath.is_absolute(relative) {
    True -> relative
    False -> filepath.join(root, relative)
  }

  filepath.expand(joined) |> result.replace_error("invalid relative directory")
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
