import envoy
import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/midas_bun
import eyg/cli/internal/source
import eyg/hub/cache.{type Cache}
import eyg/hub/publisher
import eyg/hub/release
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import filepath
import gleam/fetchx
import gleam/http/request
import gleam/int
import gleam/javascript/promise.{type Promise}
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
import touch_grass/env as env_effect
import touch_grass/fetch
import touch_grass/file_system/append_file
import touch_grass/file_system/delete_file
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file
import touch_grass/http
import touch_grass/now
import touch_grass/print
import touch_grass/random
import touch_grass/sleep
import untethered/ledger/schema

pub type State(meta) {
  State(
    cwd: String,
    config: config.Config,
    cache: Cache(meta),
    map: fn(Nil) -> meta,
  )
}

pub fn block(source, scope, state) {
  loop(block.execute(source, scope), state)
}

pub type CacheUpdate(meta) {
  Fetched(cid: v1.Cid, result: Result(ir.Node(meta), String))
  Pulled(result: Result(List(schema.ArchivedEntry), String))
}

fn loop(return, state: State(meta)) -> Promise(Result(_, _)) {
  let #(return, cache) = cache.loop(return, state.cache, block.resume)
  let state = State(..state, cache:)
  case return {
    Ok(return) -> promise.resolve(Ok(return))
    Error(#(reason, _meta, env, k)) ->
      case reason {
        break.UnhandledEffect("AppendFile", lift) -> {
          use input <- promisex.try_sync(append_file.decode(lift))
          let output = append_file(state.cwd, input)
          loop(block.resume(append_file.encode(output), env, k), state)
        }
        break.UnhandledEffect("DecodeJSON", lift) -> {
          use encoded <- promisex.try_sync(decode_json.decode(lift))
          loop(block.resume(decode_json.sync(encoded), env, k), state)
        }
        break.UnhandledEffect("DeleteFile", lift) -> {
          use path <- promisex.try_sync(delete_file.decode(lift))
          let output = delete_file(state.cwd, path)
          loop(block.resume(delete_file.encode(output), env, k), state)
        }
        break.UnhandledEffect("DNSimple", lift) -> {
          use result <- promise.try_await(service_fetch("dnsimple", lift, 8080))
          loop(block.resume(fetch.encode(result), env, k), state)
        }
        break.UnhandledEffect("Env", lift) -> {
          use name <- promisex.try_sync(env_effect.decode(lift))
          let result = envoy.get(name) |> option.from_result
          loop(block.resume(env_effect.encode(result), env, k), state)
        }
        break.UnhandledEffect("Fetch", lift) -> {
          use request <- promisex.try_sync(fetch.decode(lift))
          use result <- promise.await(fetchx.send_bits(request))
          let result = result.map_error(result, string.inspect)
          loop(block.resume(fetch.encode(result), env, k), state)
        }
        break.UnhandledEffect("GitHub", lift) -> {
          use result <- promise.try_await(service_fetch("github", lift, 8080))
          loop(block.resume(fetch.encode(result), env, k), state)
        }
        break.UnhandledEffect("Netlify", lift) -> {
          use result <- promise.try_await(service_fetch("netlify", lift, 8080))
          loop(block.resume(fetch.encode(result), env, k), state)
        }
        break.UnhandledEffect("Now", _lift) -> {
          let millis = now.sync()
          loop(block.resume(now.encode(millis), env, k), state)
        }
        break.UnhandledEffect("Print", lift) -> {
          use message <- promisex.try_sync(print.decode(lift))
          print.sync(message)
          loop(block.resume(print.encode(Nil), env, k), state)
        }
        break.UnhandledEffect("Random", lift) -> {
          use max <- promisex.try_sync(random.decode(lift))
          let n = random.sync(max)
          loop(block.resume(random.encode(n), env, k), state)
        }
        break.UnhandledEffect("ReadDirectory", lift) -> {
          use input <- promisex.try_sync(read_directory.decode(lift))
          let output = read_directory(state.cwd, input)
          loop(block.resume(read_directory.encode(output), env, k), state)
        }
        break.UnhandledEffect("ReadFile", lift) -> {
          use input <- promisex.try_sync(read_file.decode(lift))
          let output = read_file(state.cwd, input)
          loop(block.resume(read_file.encode(output), env, k), state)
        }
        break.UnhandledEffect("Sleep", lift) -> {
          use ms <- promisex.try_sync(sleep.decode(lift))
          use Nil <- promise.await(promise.wait(ms))
          loop(block.resume(sleep.encode(Nil), env, k), state)
        }
        break.UnhandledEffect("Vimeo", lift) -> {
          use result <- promise.try_await(service_fetch("vimeo", lift, 8080))
          loop(block.resume(fetch.encode(result), env, k), state)
        }
        break.UnhandledEffect("WriteFile", lift) -> {
          use input <- promisex.try_sync(write_file.decode(lift))
          let output = write_file(state.cwd, input)
          loop(block.resume(write_file.encode(output), env, k), state)
        }
        break.UndefinedReference(cid) -> {
          use value <- promise.try_await(lookup_reference(cid, state))
          loop(block.resume(value, env, k), state)
        }
        break.UndefinedRelease(package: p, release: v, module: m) -> {
          use value <- promise.try_await(lookup_release(p, v, m, state))
          loop(block.resume(value, env, k), state)
        }
        break.UndefinedRelative(location:) -> {
          use value <- promise.try_await(lookup_relative(location, state))
          loop(block.resume(value, env, k), state)
        }
        _ -> promise.resolve(Error(reason))
      }
  }
}

fn update(state: State(_)) {
  let #(cache, effects) = cache.flush(state.cache)
  case effects {
    [] -> promise.resolve(State(..state, cache:))
    _ -> {
      use applicable <- promise.await(
        promise.await_list(list.map(effects, do_effect(_, state))),
      )
      let cache = list.fold(applicable, cache, apply)
      update(State(..state, cache:))
    }
  }
}

fn do_effect(
  effect: cache.Action,
  state: State(meta),
) -> Promise(CacheUpdate(meta)) {
  let client = state.config.client
  case effect {
    cache.FetchModule(dep) -> {
      use result <- promise.map(client.get_module(dep, client))

      case result {
        Ok(Some(source)) ->
          Fetched(dep, Ok(source |> ir.map_annotation(state.map)))
        Ok(None) -> Fetched(dep, Error("unknown"))
        Error(reason) -> Fetched(dep, Error(reason))
      }
    }
    cache.PullPackages(offset:) -> {
      use result <- promise.map(client.pull_packages(offset, client))
      case result {
        Ok(response) -> Pulled(Ok(response.entries))
        Error(reason) -> Pulled(Error(reason))
      }
    }
  }
}

fn apply(cache: Cache(_), update: CacheUpdate(_)) -> Cache(_) {
  case update {
    Fetched(cid:, result:) -> {
      let #(cache, _done) = cache.fetched(cache, cid, result)
      cache
    }
    Pulled(result:) ->
      case result {
        Ok(entries) -> {
          list.fold(entries, cache, fn(cache, entry) {
            let assert Ok(payload) =
              json.parse(entry.payload, publisher.decoder())

            let publisher.Release(package:, version:, module:) = payload.content
            let release = release.Release(package:, version:, module:)
            let #(cache, _done) = cache.pulled(cache, entry.cursor, release)
            cache
          })
        }
        Error(_reason) -> {
          cache.Cache(..cache, cursor_status: cache.Pulled)
        }
      }
  }
}

fn lookup_reference(
  cid: v1.Cid,
  state: State(meta),
) -> Promise(Result(state.Value(meta), state.Reason(meta))) {
  use state <- promise.map(update(state))
  case cache.module(state.cache, cid) {
    cache.Available(cache.Module(value:, ..)) -> Ok(value)
    cache.Unavailable(reason) -> Error(reason)
    cache.Unknown -> {
      abort("failed to fetch module #" <> v1.to_string(cid))
      |> Error()
    }
  }
}

fn lookup_release(package, version, module, state: State(_)) {
  let unbound = module == dag_json.vacant_cid
  case package, version, unbound {
    _, 0, True -> {
      let cache = cache.pull(state.cache)
      use state <- promise.await(update(State(..state, cache:)))
      case cache.package(state.cache, package) {
        Ok(#(_, module)) -> lookup_reference(module, state)
        Error(Nil) -> {
          abort("package not found: @" <> package)
          |> Error
          |> promise.resolve
        }
      }
    }
    p, v, True -> {
      let cache = cache.pull(state.cache)
      use state <- promise.await(update(State(..state, cache:)))
      case cache.unbound_release(state.cache, p, v) {
        Ok(module) -> lookup_reference(module, state)
        Error(Nil) ->
          abort("package not found: @" <> p <> ":" <> int.to_string(v))
          |> Error
          |> promise.resolve
      }
    }
    _, _, _ -> {
      let cache = cache.pull(state.cache)
      use state <- promise.await(update(State(..state, cache:)))
      let release = release.Release(package:, version:, module:)
      case cache.release(state.cache, release) {
        cache.Available(resolved) -> lookup_reference(resolved, state)
        cache.Unknown -> {
          abort("module not found for package: @" <> package)
          |> Error
          |> promise.resolve
        }
        cache.Unavailable(Nil) ->
          break.UndefinedRelease(package:, release: version, module:)
          |> Error
          |> promise.resolve
      }
    }
  }
}

// used to handle cases where the runtime aborts the program
fn abort(reason: String) -> break.Reason(m, c) {
  break.UnhandledEffect("Abort", v.String(reason))
}

fn lookup_relative(
  location,
  state: State(meta),
) -> Promise(Result(state.Value(meta), state.Reason(meta))) {
  case resolve_relative(state.cwd, location) {
    Ok(path) -> {
      case source.read(path) {
        Ok(source) -> {
          let source = ir.map_annotation(source, state.map)
          pure_loop(expression.execute(source, []), state)
        }
        Error(_reason) ->
          abort("failed to read module from location: " <> location)
          |> Error
          |> promise.resolve
      }
    }
    Error(_) -> promise.resolve(Error(break.UndefinedRelative(location:)))
  }
}

pub fn pure_loop(return, state: State(_)) {
  let #(return, cache) = cache.loop(return, state.cache, expression.resume)
  let state = State(..state, cache:)
  case return {
    Ok(return) -> promise.resolve(Ok(return))
    Error(#(reason, _meta, env, k)) ->
      case reason {
        break.UndefinedReference(cid) -> {
          use value <- promise.try_await(lookup_reference(cid, state))
          pure_loop(expression.resume(value, env, k), state)
        }
        break.UndefinedRelease(package: p, release: v, module: m) -> {
          use value <- promise.try_await(lookup_release(p, v, m, state))
          pure_loop(expression.resume(value, env, k), state)
        }
        break.UndefinedRelative(location:) -> {
          use value <- promise.try_await(lookup_relative(location, state))
          pure_loop(expression.resume(value, env, k), state)
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

pub fn delete_file(cwd, path) {
  {
    use path <- try(
      resolve_relative(cwd, path) |> result.replace_error(simplifile.Enoent),
    )
    simplifile.delete(path)
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
    // TODO this could be fixed by passing an enum of services through.
    _ -> panic as "unknown service"
  }
  operation.to_request(operation, origin)
  |> request.set_header("authorization", "Bearer " <> token)
}
