//// A sealed computer. No filesystem, environment, clock, randomness, terminal
//// or subprocess operation falls through to the host. Only the broker can do IO.

import gleam/http/response

import filepath
import glasshouse/bundle
import glasshouse/sha256
import glasshouse/store
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import loam/acquire
import loam/broker
import loam/environment
import loam/sandbox/fs
import loam/system
import simplifile
import touch_grass/acquire as acquisition

pub type Layer {
  Present(BitArray)
  Removed
}

pub type Limits {
  Limits(
    effects: Int,
    written_bytes: Int,
    output_bytes: Int,
    response_bytes: Int,
  )
}

pub fn limits() -> Limits {
  Limits(100_000, 64_000_000, 1_000_000, 8_000_000)
}

pub type Machine {
  Machine(
    cwd: String,
    file_system: fs.Entry,
    files: Dict(String, Layer),
    variables: Dict(String, String),
    clock: Int,
    seed: Int,
    prompts: List(String),
    keys: List(String),
    output: List(String),
    broker: broker.Broker,
    limits: Limits,
    effects: Int,
    written_bytes: Int,
    output_bytes: Int,
    artifact_store: store.Store,
    artifact_roots: List(String),
    artifact_trees: Dict(String, fs.Entry),
    acquired_bytes: Int,
    fetcher: acquire.Fetcher,
  )
}

pub fn new(cwd: String, clock: Int, seed: Int) -> Machine {
  fork(environment.Environment(..environment.new(), cwd:, clock:, seed:))
}

/// O(1): the filesystem and its immutable byte arrays are shared by every fork.
pub fn fork(environment: environment.Environment) -> Machine {
  Machine(
    environment.cwd,
    environment.files,
    dict.new(),
    environment.variables,
    environment.clock,
    int.max(1, environment.seed % 2_147_483_647),
    [],
    [],
    [],
    broker.new(broker.Offline),
    limits(),
    0,
    0,
    0,
    environment.store,
    environment.artifacts,
    dict.new(),
    0,
    acquire.perform,
  )
}

/// Mount an explicitly supplied file. Used to construct inputs and apply variants.
pub fn with_file(machine: Machine, path: String, layer: Layer) -> Machine {
  let #(_, tree) =
    fs.create_directory(machine.file_system, filepath.directory_name(path))
  let #(_, tree) = case layer {
    Present(bytes) -> fs.write_bits(tree, path, bytes)
    Removed -> fs.delete(tree, path)
  }
  Machine(
    ..machine,
    file_system: tree,
    files: dict.insert(machine.files, path, layer),
  )
}

pub fn with_prompts(machine: Machine, prompts: List(String)) -> Machine {
  Machine(..machine, prompts:)
}

pub fn with_keys(machine: Machine, keys: List(String)) -> Machine {
  Machine(..machine, keys:)
}

pub fn with_broker(machine: Machine, mode: broker.Mode) -> Machine {
  Machine(..machine, broker: broker.new(mode))
}

pub fn changed(machine: Machine) -> Dict(String, Layer) {
  machine.files
}

pub fn run(
  effect: system.Effect(a),
  machine: Machine,
) -> system.Effect(#(Result(a, String), Machine)) {
  case effect {
    system.Done(value) ->
      system.Done(#(
        result.map(broker.finish(machine.broker), fn(_) { value }),
        machine,
      ))
    _ if machine.effects >= machine.limits.effects ->
      stop("sandbox effect budget exhausted", machine)
    _ -> step(effect, Machine(..machine, effects: machine.effects + 1))
  }
}

fn stop(reason, machine) {
  system.Done(#(Error(reason), machine))
}

fn step(effect, machine: Machine) {
  case effect {
    system.SpanStart(_, _, resume) | system.SpanEnd(_, resume) ->
      run(resume(Nil), machine)
    system.Sql(_, _, _, resume) ->
      run(
        resume(Error("host SQLite databases are not mounted in the sandbox")),
        machine,
      )
    system.TemporaryDirectory(_) ->
      stop(
        "scratch directories are only available to trusted acquisition adapters",
        machine,
      )
    system.Acquire(input, resume) -> {
      // Publish only a receipt the sandbox can retain. Invalid/over-budget
      // results become recorded acquisition errors, without retaining their blocks.
      let fetcher = fn(input) {
        use fetched <- system.map(machine.fetcher(input))
        use receipt <- result.try(fetched)
        use _ <- result.map(retain(machine, receipt, input.expected))
        receipt
      }
      use #(answer, broker) <- system.then(broker.acquire(
        machine.broker,
        input,
        fetcher,
      ))
      let machine = Machine(..machine, broker:)
      case answer {
        Error(reason) -> stop(reason, machine)
        Ok(Error(reason)) -> run(resume(Error(reason)), machine)
        Ok(Ok(receipt)) ->
          case retain(machine, receipt, input.expected) {
            Error(reason) -> stop(reason, machine)
            Ok(machine) ->
              run(
                resume(
                  Ok(acquisition.Receipt(
                    receipt.artifact.root,
                    receipt.resolved,
                  )),
                ),
                machine,
              )
          }
      }
    }
    system.Mount(input, resume) -> {
      case mounted(machine, input.root, input.path) {
        Error(reason) -> run(resume(Error(reason)), machine)
        Ok(machine) -> run(resume(Ok(Nil)), machine)
      }
    }
    system.Done(value) -> system.Done(#(Ok(value), machine))
    system.Exit(_) ->
      stop("process exit is not available inside a sandbox", machine)
    system.Cwd(resume) -> run(resume(Ok(machine.cwd)), machine)
    system.Env(name, resume) ->
      run(
        resume(dict.get(machine.variables, name) |> option.from_result),
        machine,
      )
    system.ReadFile(path, resume) -> {
      let read =
        absolute(machine, path)
        |> result.try(fs.read(machine.file_system, _))
        |> result.map_error(system.format_file_error(path, _))
      run(resume(read), machine)
    }
    system.ReadFileRange(path, offset, limit, resume) -> {
      let read =
        absolute(machine, path)
        |> result.try(fs.read_range(machine.file_system, _, offset, limit))
      run(resume(read), machine)
    }
    system.ReadDirectory(path, resume) ->
      run(
        resume(
          absolute(machine, path)
          |> result.try(fs.read_directory(machine.file_system, _)),
        ),
        machine,
      )
    system.FileInfo(path, resume) ->
      run(
        resume(
          absolute(machine, path)
          |> result.try(fs.file_info(machine.file_system, _)),
        ),
        machine,
      )
    system.WriteFile(path, text, resume) ->
      write(
        machine,
        path,
        <<text:utf8>>,
        fn(reply) { resume(result.map_error(reply, simplifile.describe_error)) },
        False,
      )
    system.WriteFileBits(path, bytes, resume) ->
      write(machine, path, bytes, resume, False)
    system.AppendFileBits(path, bytes, resume) ->
      write(machine, path, bytes, resume, True)
    system.DeleteFile(path, resume) ->
      case absolute(machine, path) {
        Error(reason) -> run(resume(Error(reason)), machine)
        Ok(path) -> {
          let #(reply, tree) = fs.delete(machine.file_system, path)
          let files = case reply {
            Ok(_) -> dict.insert(machine.files, path, Removed)
            Error(_) -> machine.files
          }
          run(resume(reply), Machine(..machine, file_system: tree, files:))
        }
      }
    system.CreateDirectory(path, resume) ->
      case absolute(machine, path) {
        Error(reason) ->
          run(resume(Error(simplifile.describe_error(reason))), machine)
        Ok(path) -> {
          let #(reply, tree) = fs.create_directory(machine.file_system, path)
          run(
            resume(result.map_error(reply, simplifile.describe_error)),
            Machine(..machine, file_system: tree),
          )
        }
      }
    system.SetPermissions(_, _, resume) ->
      run(resume(Error("sandbox files have no host permissions")), machine)
    system.Now(resume) -> run(resume(machine.clock), machine)
    system.Wait(milliseconds, resume) ->
      run(
        resume(Nil),
        Machine(..machine, clock: machine.clock + int.max(0, milliseconds)),
      )
    system.Random(max, resume) -> {
      let seed = { machine.seed * 48_271 } % 2_147_483_647
      let value = case max {
        0 -> 0
        _ if max > 0 -> seed % max
        _ -> -{ seed % -max }
      }
      run(resume(value), Machine(..machine, seed:))
    }
    system.GenerateKey(_) ->
      stop("key generation requires an explicit external capability", machine)
    system.Command(_, _, _, _) ->
      stop(
        "subprocesses are not available inside a sandbox; acquire inputs before running",
        machine,
      )
    system.Stdin(resume) ->
      run(resume(Error("standard input is not mounted")), machine)
    system.Prompt(_, resume) ->
      case machine.prompts {
        [prompt, ..prompts] ->
          run(resume(Ok(prompt)), Machine(..machine, prompts:))
        [] -> run(resume(Ok("")), machine)
      }
    system.Stdout(text, resume) -> output(text <> "\n", resume, machine)
    system.ReadKey(milliseconds, resume) ->
      case machine.keys {
        [key, ..keys] ->
          run(resume(option.Some(key)), Machine(..machine, keys:))
        [] ->
          run(
            resume(option.None),
            Machine(..machine, clock: machine.clock + int.max(0, milliseconds)),
          )
      }
    system.WriteStdout(text, resume) | system.WriteStderr(text, resume) ->
      output(text, resume, machine)
    system.Hash(algorithm, bytes, resume) ->
      run(resume(system.do_hash(algorithm, bytes)), machine)
    system.FetchStream(request, resume) -> {
      let effect =
        system.Fetch(request, fn(reply) {
          let reply =
            result.map(reply, fn(reply) {
              response.set_body(reply, system.Chunks([reply.body]))
            })
          resume(reply)
        })
      run(effect, machine)
    }
    system.ReadChunk(system.Chunks(chunks), resume) ->
      case chunks {
        [] -> run(resume(Ok(#(option.None, system.Chunks([])))), machine)
        [chunk, ..rest] ->
          run(resume(Ok(#(option.Some(chunk), system.Chunks(rest)))), machine)
      }
    system.ReadChunk(system.Body(_), _) ->
      stop("live readers are not available inside a sandbox", machine)
    system.Fetch(request, resume) ->
      case bit_array.byte_size(request.body) > machine.limits.response_bytes {
        True -> stop("external request body budget exhausted", machine)
        False -> {
          use #(reply, broker) <- system.then(broker.request(
            machine.broker,
            request,
          ))
          let machine = Machine(..machine, broker:)
          case reply {
            Error(reason) -> stop(reason, machine)
            Ok(Ok(response)) ->
              case
                bit_array.byte_size(response.body)
                > machine.limits.response_bytes
              {
                True -> stop("external response body budget exhausted", machine)
                False -> run(resume(Ok(response)), machine)
              }
            Ok(reply) -> run(resume(reply), machine)
          }
        }
      }
  }
}

fn retain(
  machine: Machine,
  receipt: acquire.Receipt,
  expected: option.Option(String),
) {
  use artifact <- result.try(acquire.verify(receipt.artifact, expected))
  use artifact <- result.try(bundle.validate(artifact, sha256.hash))
  let root = artifact.root
  use tree <- result.try(case dict.get(machine.artifact_trees, root) {
    Ok(tree) -> Ok(tree)
    Error(_) -> environment.tree(artifact)
  })
  let bytes = case list.contains(machine.artifact_roots, root) {
    True -> 0
    False -> tree_bytes(tree)
  }
  case machine.acquired_bytes + bytes > machine.limits.written_bytes {
    True -> Error("acquisition byte budget exhausted")
    False ->
      Ok(
        Machine(
          ..machine,
          artifact_store: store.merge(machine.artifact_store, artifact.store),
          artifact_roots: list.unique([root, ..machine.artifact_roots]),
          artifact_trees: dict.insert(machine.artifact_trees, root, tree),
          acquired_bytes: machine.acquired_bytes + bytes,
        ),
      )
  }
}

fn mounted(machine: Machine, root: String, path: String) {
  use path <- result.try(
    absolute(machine, path) |> result.map_error(simplifile.describe_error),
  )
  use Nil <- result.try(case list.contains(machine.artifact_roots, root) {
    True -> Ok(Nil)
    False -> Error("artifact is not retained in this environment: " <> root)
  })
  use tree <- result.try(case dict.get(machine.artifact_trees, root) {
    Ok(tree) -> Ok(tree)
    Error(_) -> environment.tree(bundle.new(root, machine.artifact_store))
  })
  let used = machine.written_bytes + tree_bytes(tree)
  use Nil <- result.try(case used > machine.limits.written_bytes {
    True -> Error("sandbox write budget exhausted")
    False -> Ok(Nil)
  })
  let #(mounted, files) = fs.mount(machine.file_system, path, tree)
  use Nil <- result.map(result.map_error(mounted, simplifile.describe_error))
  Machine(
    ..machine,
    file_system: files,
    written_bytes: used,
    artifact_trees: dict.insert(machine.artifact_trees, root, tree),
  )
}

fn tree_bytes(tree: fs.Entry) -> Int {
  case tree {
    fs.File(contents:, ..) -> bit_array.byte_size(contents)
    fs.Directory(children:, ..) ->
      dict.values(children)
      |> list.fold(0, fn(bytes, child) { bytes + tree_bytes(child) })
  }
}

fn absolute(machine: Machine, path) {
  system.resolve_relative(machine.cwd, path)
}

fn write(machine: Machine, path, bytes, resume, append) {
  let used = machine.written_bytes + bit_array.byte_size(bytes)
  case used > machine.limits.written_bytes {
    True -> stop("sandbox write budget exhausted", machine)
    False ->
      case absolute(machine, path) {
        Error(reason) -> run(resume(Error(reason)), machine)
        Ok(path) -> {
          let #(reply, tree) = case append {
            True -> fs.append_bits(machine.file_system, path, bytes)
            False -> fs.write_bits(machine.file_system, path, bytes)
          }
          let files = case reply, fs.read_bits(tree, path) {
            Ok(_), Ok(bytes) -> dict.insert(machine.files, path, Present(bytes))
            _, _ -> machine.files
          }
          run(
            resume(reply),
            Machine(..machine, file_system: tree, files:, written_bytes: used),
          )
        }
      }
  }
}

fn output(text, resume, machine: Machine) {
  let used = machine.output_bytes + bit_array.byte_size(<<text:utf8>>)
  case used > machine.limits.output_bytes {
    True -> stop("sandbox output budget exhausted", machine)
    False ->
      run(
        resume(Nil),
        Machine(..machine, output: [text, ..machine.output], output_bytes: used),
      )
  }
}
