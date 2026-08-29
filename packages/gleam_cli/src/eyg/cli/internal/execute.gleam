import envoy
import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/source
import eyg/cli/system
import eyg/hub/cache.{type Cache}
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser/location
import filepath
import gleam/bit_array
import gleam/crypto
import gleam/fetchx
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import gleam/string
import kryptos/eddsa
import multiformats/cid/v1
import shellout
import simplifile
import touch_grass/cryptography/create_key
import touch_grass/cryptography/hash
import touch_grass/cryptography/sign
import touch_grass/decode_json
import touch_grass/env as env_effect
import touch_grass/eyg_parse
import touch_grass/fetch
import touch_grass/file_system/append_file
import touch_grass/file_system/cwd
import touch_grass/file_system/delete_file
import touch_grass/file_system/make_directory
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file
import touch_grass/flip
import touch_grass/harness/computer
import touch_grass/interface
import touch_grass/now
import touch_grass/random
import touch_grass/sleep
import touch_grass/standard_error
import touch_grass/standard_in
import touch_grass/standard_out
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
  State(config: config.Config, cache: Cache(source.Location))
}

pub fn block(source, scope, state) {
  loop(block.execute(source, scope), state)
}

pub type CacheUpdate {
  Fetched(cid: v1.Cid, result: Result(ir.Node(source.Location), String))
  Pulled(result: Result(List(schema.ArchivedEntry), String))
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

/// The implementation of the harness/computer effects.
/// Implemented as promises, not based on system.Effect.
pub fn extrinsic(
  effect: computer.Effect,
  origin: source.Origin,
) -> Promise(v.Value(a, b)) {
  case effect {
    computer.AppendFile(input) -> {
      let output = append_file(origin, input)
      append_file.encode(output)
      |> promise.resolve
    }
    computer.CreateKey(request) -> {
      let output = create_key(request)
      create_key.encode(output)
      |> promise.resolve
    }
    computer.Cwd -> {
      let output = cwd()
      cwd.encode(output)
      |> promise.resolve
    }
    computer.DecodeJson(encoded) -> decode_json.sync(encoded) |> promise.resolve
    computer.DeleteFile(path:) -> {
      let output = delete_file(origin, path)
      delete_file.encode(output)
      |> promise.resolve
    }
    computer.Env(name:) -> {
      let result = envoy.get(name) |> option.from_result
      env_effect.encode(result)
      |> promise.resolve
    }
    computer.Exit(status:) -> {
      exit(status)
    }
    computer.EygParse(source:) -> {
      let result = source.parse(source, origin)
      eyg_parse.encode(result)
      |> promise.resolve
    }
    computer.Fetch(request) -> {
      use result <- promise.map(fetchx.send_bits(request))
      let result = result.map_error(result, string.inspect)
      fetch.encode(result)
    }
    computer.Flip ->
      flip.sync()
      |> flip.encode
      |> promise.resolve
    computer.Hash(input) -> hash.encode(hash(input)) |> promise.resolve
    computer.MakeDirectory(input) ->
      make_directory(input)
      |> make_directory.encode
      |> promise.resolve
    computer.Now -> {
      let millis = now.sync()
      now.encode(millis)
      |> promise.resolve
    }
    computer.Random(max) -> {
      let n = random.sync(max)
      random.encode(n) |> promise.resolve
    }
    computer.ReadDirectory(path:) -> {
      let output = read_directory(origin, path)
      read_directory.encode(output)
      |> promise.resolve
    }
    computer.ReadFile(input) -> {
      let output = read_file(origin, input)
      read_file.encode(output) |> promise.resolve
    }
    computer.Sign(request) -> {
      let output = sign(request)
      sign.encode(output)
      |> promise.resolve
    }
    computer.Sleep(ms) -> {
      use Nil <- promise.map(promise.wait(ms))
      sleep.encode(Nil)
    }
    computer.StandardError(text) -> {
      standard_error.sync(text)
      |> standard_error.encode
      |> promise.resolve
    }
    computer.StandardIn -> {
      system.read_stdin()
      |> result.map(bit_array.from_string)
      |> standard_in.encode()
      |> promise.resolve
    }
    computer.StanardOut(text) -> {
      standard_out.sync(text)
      |> standard_out.encode
      |> promise.resolve
    }
    computer.WriteFile(input) -> {
      let output = write_file(origin, input)
      write_file.encode(output)
      |> promise.resolve
    }
  }
}

pub fn loop(
  return: Result(#(Option(Value), Scope), Debug),
  state: State,
) -> Promise(Result(#(Option(Value), Scope), Debug)) {
  case return {
    Ok(return) -> promise.resolve(Ok(return))
    Error(#(reason, meta, env, k)) ->
      case reason {
        break.UnhandledEffect(label, lift) ->
          case interface.cast(computer.effects(), label, lift) {
            Ok(effect) -> {
              use value <- promise.await(extrinsic(effect, meta.origin))
              loop(block.resume(value, env, k), state)
            }

            Error(reason) -> promise.resolve(Error(#(reason, meta, env, k)))
          }

        break.UndefinedReference(ir.Content(cid)) -> {
          use value <- try_await(lookup_reference(cid, state), meta, env, k)
          loop(block.resume(value, env, k), state)
        }
        break.UndefinedReference(ir.Package(package)) -> {
          use value <- try_await(lookup_package(package, state), meta, env, k)
          loop(block.resume(value, env, k), state)
        }
        break.UndefinedReference(ir.Version(package, version)) -> {
          use value <- try_await(
            lookup_version(package, version, state),
            meta,
            env,
            k,
          )
          loop(block.resume(value, env, k), state)
        }
        break.UndefinedReference(ir.Pinned(release)) -> {
          use value <- try_await(lookup_pinned(release, state), meta, env, k)
          loop(block.resume(value, env, k), state)
        }
        break.UndefinedReference(ir.Relative(location:)) -> {
          use value <- try_await(
            lookup_relative(location, meta.origin, state),
            meta,
            env,
            k,
          )
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
      use result <- promise.map(system.run(client.get_module(dep, client)))

      case result {
        Ok(source) ->
          Fetched(
            dep,
            Ok(
              source
              |> ir.map_annotation(fn(_: Nil) {
                source.Location(source.Content(dep), source.Json)
              }),
            ),
          )
        Error(reason) -> Fetched(dep, Error(reason))
      }
    }
    cache.PullPackages(offset:) -> {
      use result <- promise.map(client.pull_packages(offset, client))
      Pulled(result)
    }
  }
}

fn apply(
  cache: Cache(source.Location),
  update: CacheUpdate,
) -> Cache(source.Location) {
  case update {
    Fetched(cid:, result:) -> {
      let #(cache, _done) = cache.fetch_module_completed(cache, cid, result)
      cache
    }
    Pulled(result:) -> {
      let #(cache, _done) = cache.pull_packages_completed(cache, result)
      cache
    }
  }
}

fn lookup_reference(
  cid: v1.Cid,
  state: State,
) -> Promise(Result(Value, Reason)) {
  // A pulled release does not fetch its module, so ask for the one being read.
  let cache = cache.fetch(state.cache, cid)
  use state <- promise.map(update(State(..state, cache:)))
  case cache.module(state.cache, cid) {
    cache.Available(cache.Module(value:, ..)) -> Ok(value)
    cache.Unavailable(reason) -> Error(reason)
    cache.Unknown -> {
      // The module itself may have been fetched successfully; this branch
      // also fires when one of its dependencies couldn't be resolved. We
      // can't yet say *which* dep is missing, but we can keep the user
      // from chasing the wrong CID.
      abort(
        "failed to load module #"
        <> v1.to_string(cid)
        <> " (the module itself or one of its dependencies could not be fetched from "
        <> "$EYG_ORIGIN)",
      )
      |> Error()
    }
  }
}

fn lookup_package(package, state: State) {
  let cache = cache.pull(state.cache)
  use state <- promise.await(update(State(..state, cache:)))
  case cache.package(state.cache, package) {
    Ok(cache.Entry(module:, ..)) -> lookup_reference(module, state)
    Error(Nil) -> {
      abort("package not found: @" <> package)
      |> Error
      |> promise.resolve
    }
  }
}

fn lookup_version(package, version, state: State) {
  let cache = cache.pull(state.cache)
  use state <- promise.await(update(State(..state, cache:)))
  case cache.unbound_release(state.cache, package, version) {
    Ok(module) -> lookup_reference(module, state)
    Error(Nil) ->
      abort("package not found: @" <> package <> ":" <> int.to_string(version))
      |> Error
      |> promise.resolve
  }
}

fn lookup_pinned(release: ir.Release, state: State) {
  let cache = cache.pull(state.cache)
  use state <- promise.await(update(State(..state, cache:)))

  case cache.release(state.cache, release) {
    cache.Available(resolved) -> lookup_reference(resolved, state)
    cache.Unknown -> {
      abort("module not found for package: @" <> release.package)
      |> Error
      |> promise.resolve
    }
    cache.Unavailable(Nil) ->
      break.UndefinedReference(ir.Pinned(release:))
      |> Error
      |> promise.resolve
  }
}

// used to handle cases where the runtime aborts the program
fn abort(reason: String) -> break.Reason(m, c) {
  break.UnhandledEffect("Abort", v.String(reason))
}

fn lookup_relative(
  location: String,
  origin: source.Origin,
  state: State,
) -> Promise(Result(Value, Reason)) {
  case resolve_filepath(origin, location) {
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
    Error(_) ->
      promise.resolve(Error(break.UndefinedReference(ir.Relative(location:))))
  }
}

pub fn pure_loop(
  return: Result(Value, Debug),
  state: State,
) -> Promise(Result(Value, Debug)) {
  case return {
    Ok(return) -> promise.resolve(Ok(return))
    Error(#(reason, meta, env, k)) ->
      case reason {
        break.UndefinedReference(ir.Content(cid)) -> {
          use value <- try_await(lookup_reference(cid, state), meta, env, k)
          pure_loop(expression.resume(value, env, k), state)
        }
        break.UndefinedReference(ir.Package(package)) -> {
          use value <- try_await(lookup_package(package, state), meta, env, k)
          pure_loop(expression.resume(value, env, k), state)
        }
        break.UndefinedReference(ir.Version(package, version)) -> {
          use value <- try_await(
            lookup_version(package, version, state),
            meta,
            env,
            k,
          )
          pure_loop(expression.resume(value, env, k), state)
        }
        break.UndefinedReference(ir.Pinned(release)) -> {
          use value <- try_await(lookup_pinned(release, state), meta, env, k)
          pure_loop(expression.resume(value, env, k), state)
        }
        break.UndefinedReference(ir.Relative(location:)) -> {
          use value <- try_await(
            lookup_relative(location, meta.origin, state),
            meta,
            env,
            k,
          )
          pure_loop(expression.resume(value, env, k), state)
        }
        _ -> promise.resolve(Error(#(reason, meta, env, k)))
      }
  }
}

pub fn normalize_input(working_directory, input: source.Input) {
  case input {
    source.File(path:) -> {
      use path <- try(resolve_relative(working_directory, path))
      Ok(source.File(path))
    }
    source.Code(_) | source.Stdin -> Ok(input)
  }
}

pub fn resolve_relative(root, relative) {
  let joined = case filepath.is_absolute(relative) {
    True -> relative
    False -> filepath.join(root, relative)
  }
  filepath.expand(joined)
  |> result.replace_error("invalid relative path outside filesystem")
}

pub fn resolve_filepath(
  from: source.Origin,
  path: String,
) -> Result(String, String) {
  use joined <- try(case filepath.is_absolute(path) {
    True -> Ok(path)
    False ->
      case from {
        source.Disk(path: source_path) ->
          source_path
          |> filepath.directory_name()
          |> filepath.join(path)
          |> Ok
        _ ->
          Error(
            "relative path \""
            <> path
            <> "\" requires a disk-backed source; use CWD or an absolute path",
          )
      }
  })

  filepath.expand(joined)
  |> result.replace_error("invalid relative path outside filesystem")
}

pub fn hash(input) {
  let hash.Input(algorithm:, bytes:) = input
  case algorithm {
    hash.Sha256 -> crypto.hash(crypto.Sha256, bytes)
  }
}

pub fn make_directory(path: String) -> Result(Nil, String) {
  simplifile.create_directory_all(path)
  |> result.map_error(simplifile.describe_error)
}

pub fn create_key(request) {
  case request {
    create_key.Eddsa -> {
      let #(private_key, public_key) = eddsa.generate_key_pair(eddsa.Ed25519)
      Ok(create_key.EddsaKey(
        public_key: eddsa.public_key_to_bytes(public_key),
        private_key: eddsa.to_bytes(private_key),
      ))
    }
  }
}

pub fn sign(request) {
  case request {
    sign.EddsaSign(private_key:, data:) ->
      case eddsa.from_bytes(eddsa.Ed25519, private_key) {
        Ok(#(key, _public)) -> Ok(eddsa.sign(key, data))
        Error(Nil) -> Error("invalid Ed25519 private key")
      }
  }
}

pub fn append_file(
  origin: source.Origin,
  input: append_file.Input,
) -> Result(Nil, String) {
  let append_file.Input(path:, contents:) = input
  use path <- try(resolve_filepath(origin, path))

  simplifile.append_bits(path, contents)
  |> result.map_error(simplifile.describe_error)
}

pub fn cwd() {
  simplifile.current_directory()
  |> result.map_error(simplifile.describe_error)
}

pub fn read_directory(
  origin: source.Origin,
  path path: String,
) -> read_directory.Output {
  use path <- try(resolve_filepath(origin, path))
  use children <- try(
    simplifile.read_directory(path)
    |> result.map_error(simplifile.describe_error),
  )
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
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  Ok(children)
}

@external(javascript, "./execute_ffi.mjs", "readAtOffset")
fn read_at_offset(
  path path: String,
  offset offset: Int,
  limit limit: Int,
) -> Result(BitArray, simplifile.FileError)

pub fn read_file(origin: source.Origin, input: read_file.Input) {
  let read_file.Input(path:, limit:, offset:) = input
  use path <- try(resolve_filepath(origin, path))
  read_at_offset(path:, limit:, offset:)
  |> result.map_error(simplifile.describe_error)
}

pub fn write_file(origin: source.Origin, input: write_file.Input) {
  let write_file.Input(path:, contents:) = input
  use path <- try(resolve_filepath(origin, path))
  simplifile.write_bits(path, contents)
  |> result.map_error(simplifile.describe_error)
}

pub fn delete_file(origin: source.Origin, path) {
  use path <- try(resolve_filepath(origin, path))
  simplifile.delete(path)
  |> result.map_error(simplifile.describe_error)
}

/// Stop the process. Nothing follows, which is why the harness lowers `Exit`
/// to `Never`.
fn exit(status: Int) -> a {
  shellout.exit(status)
  panic as "the process did not stop"
}

// fn spotless_context() -> context.Context(Promise(t), Nil) {
//   context.Context(
//     export_jwk: fn(_key) { panic as "export_jwk not implemented" },
//     follow: bun_platform.follow,
//     fetch: bun_platform.fetch,
//     hash: bun_platform.hash,
//     sign: fn(_, _, _) { panic as "sign not implemented" },
//     strong_random: bun_platform.strong_random,
//     unix_now: fn() { panic as "unix_now not implemented" },
//   )
// }

// fn service_fetch(service, operation) {
//   let port = 8080
//   use result <- promise.await(spotless.authenticate(
//     service,
//     [],
//     "",
//     port,
//     pkce.S256,
//     spotless_context(),
//   )(promise.resolve))
//   use result <- promise.await(case result {
//     Ok(token.Response(access_token:, ..)) -> {
//       let request = service_request(service, operation, access_token)
//       use result <- promise.map(fetchx.send_bits(request))
//       result.map_error(result, string.inspect)
//     }
//     Error(reason) -> promise.resolve(Error(reason))
//   })
//   promise.resolve(Ok(result))
// }

// fn service_request(service, operation, token) {
//   let origin = case service {
//     "dnsimple" -> origin.https("api.dnsimple.com")
//     "github" -> origin.https("api.github.com")
//     "netlify" -> origin.https("api.netlify.com")
//     "tavily" -> origin.https("api.tavily.com")
//     "vimeo" -> origin.https("api.vimeo.com")
//     // TODO this could be fixed by passing an enum of services through.
//     _ -> panic as "unknown service"
//   }
//   operation.to_request(operation, origin)
//   |> request.set_header("authorization", "Bearer " <> token)
// }

/// One frame of the runtime stack trace - the failing expression's
/// meta (with `arg: None`) plus every closure call recorded by a
/// Trace frame on the continuation stack (with `arg: Some(value)`).
pub type Frame {
  Frame(location: source.Location, arg: Option(Value))
}

/// Render a runtime error as a stack trace.
///
/// Collects the failing expression's meta plus every `Trace` frame on
/// the continuation stack and renders one line per frame innermost
/// first. The deepest frame whose origin is a user-code origin (i.e.
/// not `Content` or `Release`) is marked with `→` and shown with a
/// source snippet + caret; other frames are summarised as
/// `in <label>:<line> (<arg value>)`.
pub fn render_error(
  reason: Reason,
  location: source.Location,
  stack: Stack,
  cwd: String,
) -> String {
  let frames = [Frame(location, None), ..collect_traces(stack, [])]
  let description = simple_debug.describe(reason)
  let hint = simple_debug.hint(reason)
  let header = ["error: " <> description, "hint: " <> hint]
  let focus = find_focus(frames, 0)
  // echo focus
  // let frames = list.drop(frames, focus |> option.unwrap(0))
  // let frames = list.take(frames, 3)
  // echo "here"
  let trace_lines = render_frames(frames, focus, 0, cwd, [])
  case trace_lines {
    [] -> string.join(header, "\n")
    _ -> string.join(list.append(header, ["", ..trace_lines]), "\n")
  }
}

fn collect_traces(stack: Stack, acc: List(Frame)) -> List(Frame) {
  case stack {
    state.Empty -> list.reverse(acc)
    state.Stack(state.Trace(arg), meta, rest) ->
      collect_traces(rest, [Frame(meta, Some(arg)), ..acc])
    state.Stack(_, _, rest) -> collect_traces(rest, acc)
  }
}

/// Index of the deepest frame written by the user (i.e. backed by a
/// file, the REPL, inline code, or stdin).
fn find_focus(frames: List(Frame), i: Int) -> Option(Int) {
  case frames {
    [] -> None
    [Frame(source.Location(origin, _), _), ..rest] ->
      case origin {
        source.Content(_) | source.Release(..) -> find_focus(rest, i + 1)
        _ -> Some(i)
      }
  }
}

fn render_frames(
  frames: List(Frame),
  focus: Option(Int),
  i: Int,
  cwd: String,
  acc: List(String),
) -> List(String) {
  case frames {
    [] -> list.reverse(acc)
    [frame, ..rest] -> {
      let is_focus = focus == Some(i)
      let lines = render_frame(frame, is_focus, cwd)
      render_frames(
        rest,
        focus,
        i + 1,
        cwd,
        list.fold(lines, acc, fn(acc, line) { [line, ..acc] }),
      )
    }
  }
}

fn render_frame(frame: Frame, is_focus: Bool, cwd: String) -> List(String) {
  let Frame(source.Location(origin, source), arg) = frame
  let label = origin_label(origin, cwd)
  let prefix = case is_focus {
    True -> "→ in "
    False -> "  in "
  }
  let suffix = case arg {
    Some(value) -> " (" <> simple_debug.inspect(value) <> ")"
    None -> ""
  }
  case source {
    source.Text(code:, span:) -> {
      let #(start, _) = span
      let line_no = line_at(code, start)
      let header = case line_no {
        0 -> prefix <> label <> suffix
        n -> prefix <> label <> ":" <> int.to_string(n) <> suffix
      }
      case is_focus {
        True -> [header, ..location.source_context(code, span)]
        False -> [header]
      }
    }
    source.Json ->
      case is_focus {
        True -> [prefix <> label <> " (no source)" <> suffix]
        False -> [prefix <> label <> suffix]
      }
  }
}

fn origin_label(origin: source.Origin, cwd: String) -> String {
  case origin {
    source.Disk(path:) -> string.replace(path, cwd <> "/", "")
    source.Pipe -> "<pipe>"
    source.Inline -> "<inline>"
    source.Repl -> "<repl>"
    source.Content(cid:) -> "#" <> v1.to_string(cid)
    source.Release(package:, version:, cid: _) ->
      "@" <> package <> ":" <> int.to_string(version)
  }
}

/// 1-based line number for a byte offset into `code`. Returns 0 when
/// `code` is empty.
fn line_at(code: String, offset: Int) -> Int {
  case code {
    "" -> 0
    _ -> string.slice(code, 0, offset) |> string.split("\n") |> list.length
  }
}
