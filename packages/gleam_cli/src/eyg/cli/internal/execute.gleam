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
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser/location
import filepath
import gleam/fetchx
import gleam/http/request
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
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
  State(cwd: String, config: config.Config, cache: Cache(source.Location))
}

pub fn block(source, scope, state) {
  loop(block.execute(source, scope), state)
}

pub type CacheUpdate {
  Fetched(cid: v1.Cid, result: Result(ir.Node(source.Location), String))
  Pulled(result: Result(List(schema.ArchivedEntry), String))
}

// helper that rebuilds debug context of error
fn try_sync(
  result: Result(t, Reason),
  meta: source.Location,
  env: Env,
  k: Stack,
  then: fn(t) -> Promise(Result(#(Option(Value), Scope), Debug)),
) -> Promise(Result(#(Option(Value), Scope), Debug)) {
  case result {
    Ok(value) -> then(value)
    Error(reason) -> promise.resolve(Error(#(reason, meta, env, k)))
  }
}

fn try_await(
  result: Promise(Result(t, Reason)),
  meta: source.Location,
  env: Env,
  k: Stack,
  then: fn(t) -> Promise(Result(r, Debug)),
) -> Promise(Result(r, Debug)) {
  use result <- promise.await(result)
  case result {
    Ok(value) -> then(value)
    Error(reason) -> promise.resolve(Error(#(reason, meta, env, k)))
  }
}

fn loop(return, state: State) -> Promise(Result(#(Option(Value), Scope), Debug)) {
  let #(return, cache) = cache.loop(return, state.cache, block.resume)
  let state = State(..state, cache:)
  case return {
    Ok(return) -> promise.resolve(Ok(return))
    Error(#(reason, meta, env, k)) ->
      case reason {
        break.UnhandledEffect("AppendFile", lift) -> {
          use input <- try_sync(append_file.decode(lift), meta, env, k)
          let output = append_file(state.cwd, input)
          loop(block.resume(append_file.encode(output), env, k), state)
        }
        break.UnhandledEffect("DecodeJSON", lift) -> {
          use encoded <- try_sync(decode_json.decode(lift), meta, env, k)
          loop(block.resume(decode_json.sync(encoded), env, k), state)
        }
        break.UnhandledEffect("DeleteFile", lift) -> {
          use path <- try_sync(delete_file.decode(lift), meta, env, k)
          let output = delete_file(state.cwd, path)
          loop(block.resume(delete_file.encode(output), env, k), state)
        }
        break.UnhandledEffect("DNSimple", lift) -> {
          use operation <- try_sync(http.operation_to_gleam(lift), meta, env, k)
          use result <- promise.try_await(service_fetch("dnsimple", operation))
          loop(block.resume(fetch.encode(result), env, k), state)
        }
        break.UnhandledEffect("Env", lift) -> {
          use name <- try_sync(env_effect.decode(lift), meta, env, k)
          let result = envoy.get(name) |> option.from_result
          loop(block.resume(env_effect.encode(result), env, k), state)
        }
        break.UnhandledEffect("Fetch", lift) -> {
          use request <- try_sync(fetch.decode(lift), meta, env, k)
          use result <- promise.await(fetchx.send_bits(request))
          let result = result.map_error(result, string.inspect)
          loop(block.resume(fetch.encode(result), env, k), state)
        }
        break.UnhandledEffect("GitHub", lift) -> {
          use operation <- try_sync(http.operation_to_gleam(lift), meta, env, k)
          use result <- promise.try_await(service_fetch("github", operation))
          loop(block.resume(fetch.encode(result), env, k), state)
        }
        break.UnhandledEffect("Netlify", lift) -> {
          use operation <- try_sync(http.operation_to_gleam(lift), meta, env, k)
          use result <- promise.try_await(service_fetch("netlify", operation))
          loop(block.resume(fetch.encode(result), env, k), state)
        }
        break.UnhandledEffect("Now", _lift) -> {
          let millis = now.sync()
          loop(block.resume(now.encode(millis), env, k), state)
        }
        break.UnhandledEffect("Print", lift) -> {
          use message <- try_sync(print.decode(lift), meta, env, k)
          print.sync(message)
          loop(block.resume(print.encode(Nil), env, k), state)
        }
        break.UnhandledEffect("Random", lift) -> {
          use max <- try_sync(random.decode(lift), meta, env, k)
          let n = random.sync(max)
          loop(block.resume(random.encode(n), env, k), state)
        }
        break.UnhandledEffect("ReadDirectory", lift) -> {
          use input <- try_sync(read_directory.decode(lift), meta, env, k)
          let output = read_directory(state.cwd, input)
          loop(block.resume(read_directory.encode(output), env, k), state)
        }
        break.UnhandledEffect("ReadFile", lift) -> {
          use input <- try_sync(read_file.decode(lift), meta, env, k)
          let output = read_file(state.cwd, input)
          loop(block.resume(read_file.encode(output), env, k), state)
        }
        break.UnhandledEffect("Sleep", lift) -> {
          use ms <- try_sync(sleep.decode(lift), meta, env, k)
          use Nil <- promise.await(promise.wait(ms))
          loop(block.resume(sleep.encode(Nil), env, k), state)
        }
        break.UnhandledEffect("Vimeo", lift) -> {
          use operation <- try_sync(http.operation_to_gleam(lift), meta, env, k)
          use result <- promise.try_await(service_fetch("vimeo", operation))
          loop(block.resume(fetch.encode(result), env, k), state)
        }
        break.UnhandledEffect("WriteFile", lift) -> {
          use input <- try_sync(write_file.decode(lift), meta, env, k)
          let output = write_file(state.cwd, input)
          loop(block.resume(write_file.encode(output), env, k), state)
        }
        break.UndefinedReference(cid) -> {
          use value <- try_await(lookup_reference(cid, state), meta, env, k)
          loop(block.resume(value, env, k), state)
        }
        break.UndefinedRelease(package: p, release: v, module: m) -> {
          use value <- try_await(lookup_release(p, v, m, state), meta, env, k)
          loop(block.resume(value, env, k), state)
        }
        break.UndefinedRelative(location:) -> {
          use value <- try_await(lookup_relative(location, state), meta, env, k)
          loop(block.resume(value, env, k), state)
        }
        _ -> promise.resolve(Error(#(reason, meta, env, k)))
      }
  }
}

fn update(state: State) {
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

fn do_effect(effect: cache.Action, state: State) -> Promise(CacheUpdate) {
  let client = state.config.client
  case effect {
    cache.FetchModule(dep) -> {
      use result <- promise.map(client.get_module(dep, client))

      case result {
        Ok(Some(source)) ->
          Fetched(
            dep,
            Ok(
              source
              |> ir.map_annotation(fn(_: Nil) {
                source.Location(source.Content(dep), source.Json)
              }),
            ),
          )
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

fn apply(
  cache: Cache(source.Location),
  update: CacheUpdate,
) -> Cache(source.Location) {
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

fn lookup_reference(cid: v1.Cid, state: State) -> Promise(Result(Value, Reason)) {
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

fn lookup_release(package, version, module, state: State) {
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

fn lookup_relative(location, state: State) -> Promise(Result(Value, Reason)) {
  case resolve_relative(state.cwd, location) {
    Ok(path) -> {
      case source.read_file(path) {
        Ok(code) ->
          case source.parse(code, source.Disk(path:)) {
            Ok(source) -> {
              use result <- promise.await(pure_loop(
                expression.execute(source, []),
                state,
              ))
              case result {
                Ok(value) -> promise.resolve(Ok(value))
                Error(#(reason, _, _, _)) -> promise.resolve(Error(reason))
              }
            }
            Error(_) ->
              abort("failed to read parse source from location: " <> location)
              |> Error
              |> promise.resolve
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

pub fn pure_loop(
  return: Result(Value, Debug),
  state: State,
) -> Promise(Result(Value, Debug)) {
  let #(return, cache) = cache.loop(return, state.cache, expression.resume)
  let state = State(..state, cache:)
  case return {
    Ok(return) -> promise.resolve(Ok(return))
    Error(#(reason, meta, env, k)) ->
      case reason {
        break.UndefinedReference(cid) -> {
          use value <- try_await(lookup_reference(cid, state), meta, env, k)
          pure_loop(expression.resume(value, env, k), state)
        }
        break.UndefinedRelease(package: p, release: v, module: m) -> {
          use value <- try_await(lookup_release(p, v, m, state), meta, env, k)
          pure_loop(expression.resume(value, env, k), state)
        }
        break.UndefinedRelative(location:) -> {
          use value <- try_await(lookup_relative(location, state), meta, env, k)
          pure_loop(expression.resume(value, env, k), state)
        }
        _ -> promise.resolve(Error(#(reason, meta, env, k)))
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

fn service_fetch(service, operation) {
  let port = 8080
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

pub fn render_error(
  reason: Reason,
  location: source.Location,
  cwd: String,
) -> String {
  let description = simple_debug.describe(reason)
  let hint = simple_debug.hint(reason)
  let source.Location(origin, source) = location
  let origin = case origin {
    source.Disk(path:) -> string.replace(path, cwd <> "/", "")
    source.Pipe -> "<pipe>"
    source.Inline -> "<inline>"
    source.Repl -> "<repl>"
    source.Content(cid:) -> "#" <> v1.to_string(cid)
    source.Release(package:, version:, cid: _) ->
      "@" <> package <> ":" <> int.to_string(version)
  }

  let lines = ["error: " <> description, "hint: " <> hint]
  let context = case source {
    source.Text(code:, span:) -> [
      "",
      " " <> origin,
      ..location.source_context(code, span)
    ]
    source.Json -> ["", " " <> origin]
  }
  string.join(list.append(lines, context), "\n")
}
