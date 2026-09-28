//// Runs `system.Effect` values against an in-memory model of a computer system.
////
//// - File permissions are stored as metadata but do not restrict reads or writes.
//// - Captured stdout is stored newest-first; reverse the list for emission order.
////   `stdout_text` and `stderr_text` preserve exact stream text and newlines.
//// - Key generation uses real randomness, so generated keys vary between runs.
//// - The clock defaults to Unix time zero; random results require explicit fixtures.

import filepath
import gleam/dict.{type Dict}
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option
import gleam/result
import loam/internal/crypto.{generate_key} as _
import loam/sandbox/fs
import loam/system
import midas/effect
import simplifile

pub type Sandbox(a) {
  Sandbox(
    cwd: String,
    stdin: List(String),
    stdout: List(String),
    stderr: List(String),
    environment: Dict(String, String),
    now: Int,
    random_values: List(Int),
    file_system: fs.Entry,
    network_state: a,
    network: fn(request.Request(BitArray), a) ->
      #(Result(response.Response(BitArray), effect.FetchError), a),
  )
}

pub fn sandbox() -> Sandbox(Nil) {
  Sandbox(
    cwd: "/",
    stdin: [],
    stdout: [],
    stderr: [],
    environment: dict.new(),
    now: 0,
    random_values: [],
    file_system: fs.directory([]),
    network_state: Nil,
    network: fn(_, _) { #(Error(effect.NetworkError("None provided")), Nil) },
  )
}

pub type Outcome(a) {
  Returned(a)
  Exited(Int)
}

pub fn with_env(
  sandbox: Sandbox(a),
  name: String,
  value: String,
) -> Sandbox(a) {
  Sandbox(..sandbox, environment: dict.insert(sandbox.environment, name, value))
}

/// Configure the wall clock in Unix milliseconds.
pub fn with_now(sandbox: Sandbox(a), milliseconds: Int) -> Sandbox(a) {
  Sandbox(..sandbox, now: milliseconds)
}

/// Supply random results in consumption order; missing or out-of-range fixtures fail the test.
pub fn with_random_values(
  sandbox: Sandbox(a),
  values: List(Int),
) -> Sandbox(a) {
  Sandbox(..sandbox, random_values: values)
}

/// This sets the CWD as is, it ignores the current cwd
pub fn with_cwd(sandbox: Sandbox(a), cwd: String) -> Sandbox(a) {
  Sandbox(..sandbox, cwd:)
}

pub fn with_stdin(sandbox: Sandbox(a), text: String) -> Sandbox(a) {
  Sandbox(..sandbox, stdin: list.append(sandbox.stdin, [text]))
}

pub fn with_files(
  sandbox: Sandbox(a),
  files: List(#(String, String)),
) -> Sandbox(a) {
  list.fold(files, sandbox, fn(sandbox, file) {
    with_file(sandbox, file.0, file.1)
  })
}

/// add a file to the filesystem, needs to be absolute path
pub fn with_file(
  sandbox: Sandbox(a),
  path: String,
  content: String,
) -> Sandbox(a) {
  with_file_bits(sandbox, path, <<content:utf8>>)
}

/// Add binary contents at an absolute fixture path.
pub fn with_file_bits(
  sandbox: Sandbox(a),
  path: String,
  content: BitArray,
) -> Sandbox(a) {
  let #(created, file_system) =
    fs.create_directory(sandbox.file_system, filepath.directory_name(path))
  let assert Ok(Nil) = created
  let #(written, file_system) = fs.write_bits(file_system, path, content)
  let assert Ok(Nil) = written
  Sandbox(..sandbox, file_system:)
}

/// Needs absolute path
pub fn with_directory(sandbox: Sandbox(a), path: String) -> Sandbox(a) {
  let #(created, file_system) = fs.create_directory(sandbox.file_system, path)
  let assert Ok(Nil) = created
  Sandbox(..sandbox, file_system:)
}

/// needs absolute path
pub fn with_permissions(
  sandbox: Sandbox(a),
  path: String,
  permissions: Int,
) -> Sandbox(a) {
  let #(set, file_system) =
    fs.set_permissions(sandbox.file_system, path, permissions)
  let assert Ok(Nil) = set
  Sandbox(..sandbox, file_system:)
}

pub fn with_network(
  sandbox: Sandbox(_),
  network: fn(request.Request(BitArray), a) ->
    #(Result(response.Response(BitArray), effect.FetchError), a),
  network_state: a,
) -> Sandbox(a) {
  Sandbox(..sandbox, network:, network_state:)
}

pub fn save_and_return(sandbox, response) {
  with_network(
    sandbox,
    fn(request, acc) { #(Ok(response), [request, ..acc]) },
    [],
  )
}

fn mutate_file_system(sandbox: Sandbox(a), path, mutate) {
  case system.resolve_relative(sandbox.cwd, path) {
    Error(error) -> #(Error(error), sandbox)
    Ok(path) -> {
      let #(outcome, file_system) = mutate(sandbox.file_system, path)
      #(outcome, Sandbox(..sandbox, file_system:))
    }
  }
}

/// Run a workflow expected to complete normally. Use `run_until_exit` to test process exit.
pub fn run(
  effect: system.Effect(a),
  sandbox: Sandbox(b),
) -> #(Outcome(a), Sandbox(b)) {
  case effect {
    system.Done(value) -> #(Returned(value), sandbox)
    system.Exit(status) -> #(Exited(status), sandbox)
    system.Env(name, resume) ->
      run(
        resume(dict.get(sandbox.environment, name) |> option.from_result),
        sandbox,
      )
    system.Now(resume) -> run(resume(sandbox.now), sandbox)
    system.Random(max, resume) -> {
      let assert [value, ..rest] = sandbox.random_values
      let assert True = case max {
        0 -> value == 0
        max if max > 0 -> value >= 0 && value < max
        _ -> value >= max && value < 0
      }
      run(resume(value), Sandbox(..sandbox, random_values: rest))
    }
    system.FileInfo(path, resume) -> {
      let info =
        system.resolve_relative(sandbox.cwd, path)
        |> result.try(fs.file_info(sandbox.file_system, _))
      run(resume(info), sandbox)
    }
    system.ReadFileRange(path, offset, limit, resume) -> {
      let contents =
        system.resolve_relative(sandbox.cwd, path)
        |> result.try(fn(path) {
          fs.read_range(sandbox.file_system, path, offset, limit)
        })
      run(resume(contents), sandbox)
    }
    system.WriteFileBits(path, bytes, resume) -> {
      let #(outcome, sandbox) =
        mutate_file_system(sandbox, path, fn(fs, path) {
          fs.write_bits(fs, path, bytes)
        })
      run(resume(outcome), sandbox)
    }
    system.AppendFileBits(path, bytes, resume) -> {
      let #(outcome, sandbox) =
        mutate_file_system(sandbox, path, fn(fs, path) {
          fs.append_bits(fs, path, bytes)
        })
      run(resume(outcome), sandbox)
    }
    system.DeleteFile(path, resume) -> {
      let #(outcome, sandbox) = mutate_file_system(sandbox, path, fs.delete)
      run(resume(outcome), sandbox)
    }
    system.WriteStdout(text, resume) -> {
      let sandbox = Sandbox(..sandbox, stdout: [text, ..sandbox.stdout])
      run(resume(Nil), sandbox)
    }
    system.WriteStderr(text, resume) -> {
      run(resume(Nil), Sandbox(..sandbox, stderr: [text, ..sandbox.stderr]))
    }
    system.CreateDirectory(path, resume) -> {
      let #(outcome, sandbox) =
        mutate_file_system(sandbox, path, fs.create_directory)
      outcome
      |> result.map_error(simplifile.describe_error)
      |> resume
      |> run(sandbox)
    }
    system.Cwd(resume) -> run(resume(Ok(sandbox.cwd)), sandbox)
    system.Fetch(request, resume) -> {
      let #(response, state) = sandbox.network(request, sandbox.network_state)
      let sandbox = Sandbox(..sandbox, network_state: state)
      response
      |> resume
      |> run(sandbox)
    }
    system.GenerateKey(resume) ->
      generate_key()
      |> resume
      |> run(sandbox)
    system.Hash(algorithm, bytes, resume) ->
      system.do_hash(algorithm, bytes)
      |> resume()
      |> run(sandbox)
    system.ReadDirectory(path, resume) -> {
      system.resolve_relative(sandbox.cwd, path)
      |> result.try(fs.read_directory(sandbox.file_system, _))
      |> resume
      |> run(sandbox)
    }
    system.ReadFile(path, resume) -> {
      system.resolve_relative(sandbox.cwd, path)
      |> result.try(fs.read(sandbox.file_system, _))
      |> result.map_error(fn(error) { system.format_file_error(path, error) })
      |> resume()
      |> run(sandbox)
    }
    system.SetPermissions(path, permissions, resume) -> {
      let #(outcome, sandbox) =
        mutate_file_system(sandbox, path, fn(file_system, path) {
          fs.set_permissions(file_system, path, permissions)
        })
      outcome
      |> result.map_error(simplifile.describe_error)
      |> resume
      |> run(sandbox)
    }
    system.Stdin(resume) -> {
      let #(response, stdin) = case sandbox.stdin {
        [] -> #(Error(""), [])
        [value, ..rest] -> #(Ok(value), rest)
      }
      let sandbox = Sandbox(..sandbox, stdin:)
      run(resume(response), sandbox)
    }
    system.Stdout(text, resume) -> {
      let stdout = [text, ..sandbox.stdout]
      let sandbox = Sandbox(..sandbox, stdout:)
      run(resume(Nil), sandbox)
    }
    system.Wait(_, resume) -> run(resume(Nil), sandbox)
    system.WriteFile(path, content, resume) -> {
      let #(outcome, sandbox) =
        mutate_file_system(sandbox, path, fn(file_system, path) {
          fs.write(file_system, path, content)
        })
      outcome
      |> result.map_error(simplifile.describe_error)
      |> resume
      |> run(sandbox)
    }
  }
}
