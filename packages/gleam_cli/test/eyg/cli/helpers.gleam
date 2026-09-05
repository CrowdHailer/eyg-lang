import eyg/cli/helpers/fs
import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/crypto.{generate_key} as _
import eyg/cli/internal/platform
import eyg/cli/system
import eyg/hub/schema
import eyg/ir/car
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import filepath
import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import midas/continuation
import midas/effect
import multiformats/cid/v1
import ogre/origin
import simplifile

const eyg_origin: client.Client = client.Client(
  origin: origin.Origin(http.Https, "eyg.run", None),
)

pub const config: config.Config = config.Config(
  client: eyg_origin,
  dirs: platform.PlatformDirs(config_dir: "", cache_dir: "", data_dir: ""),
)

pub type Sandbox(a) {
  Sandbox(
    stdin: List(String),
    stdout: List(String),
    file_system: fs.Entry,
    network_state: a,
    network: fn(request.Request(BitArray), a) ->
      #(Result(response.Response(BitArray), effect.FetchError), a),
  )
}

pub fn sandbox() -> Sandbox(Nil) {
  Sandbox(
    stdin: [],
    stdout: [],
    file_system: fs.directory([]),
    network_state: Nil,
    network: fn(_, _) { #(Error(effect.NetworkError("None provided")), Nil) },
  )
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

pub fn with_file(
  sandbox: Sandbox(a),
  path: String,
  content: String,
) -> Sandbox(a) {
  let #(created, file_system) =
    fs.create_directory(sandbox.file_system, filepath.directory_name(path))
  let assert Ok(Nil) = created
  let #(written, file_system) = fs.write(file_system, path, content)
  let assert Ok(Nil) = written
  Sandbox(..sandbox, file_system:)
}

pub fn with_directory(sandbox: Sandbox(a), path: String) -> Sandbox(a) {
  let #(created, file_system) = fs.create_directory(sandbox.file_system, path)
  let assert Ok(Nil) = created
  Sandbox(..sandbox, file_system:)
}

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

pub fn vacant_cid_response() {
  response.new(200)
  |> response.set_body(
    schema.share_response_encode(dag_json.vacant_cid)
    |> json.to_string
    |> bit_array.from_string,
  )
}

pub fn share_server(sandbox: Sandbox(_)) {
  with_network(
    sandbox,
    fn(request, acc) {
      let assert Ok(archive) = car.decode(request.body)
      let assert [root] = archive.header.roots
      let response =
        response.new(200)
        |> response.set_body(
          schema.share_response_encode(root)
          |> json.to_string
          |> bit_array.from_string,
        )
      #(Ok(response), [request, ..acc])
    },
    [],
  )
}

pub fn run(effect: system.Effect(a), sandbox: Sandbox(b)) -> #(a, Sandbox(b)) {
  case effect {
    system.Done(value) -> #(value, sandbox)
    system.CreateDirectory(path, resume) -> {
      let #(outcome, file_system) =
        fs.create_directory(sandbox.file_system, path)
      let sandbox = Sandbox(..sandbox, file_system:)
      outcome
      |> result.map_error(simplifile.describe_error)
      |> resume
      |> run(sandbox)
    }
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
    system.Hash(algorithm, bytes, resume) -> {
      let algorithm = case algorithm {
        effect.Sha1 -> crypto.Sha1
        effect.Sha256 -> crypto.Sha256
        effect.Sha384 -> crypto.Sha384
        effect.Sha512 -> crypto.Sha512
      }
      crypto.hash(algorithm, bytes)
      |> resume
      |> run(sandbox)
    }
    system.ReadDirectory(path, resume) -> {
      fs.read_directory(sandbox.file_system, path)
      |> resume
      |> run(sandbox)
    }
    system.ReadFile(path, resume) -> {
      fs.read(sandbox.file_system, path)
      |> result.map_error(fn(error) { system.format_file_error(path, error) })
      |> resume()
      |> run(sandbox)
    }
    system.SetPermissions(path, permissions, resume) -> {
      let #(outcome, file_system) =
        fs.set_permissions(sandbox.file_system, path, permissions)
      let sandbox = Sandbox(..sandbox, file_system:)
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
      let #(outcome, file_system) = fs.write(sandbox.file_system, path, content)
      let sandbox = Sandbox(..sandbox, file_system:)
      outcome
      |> result.map_error(simplifile.describe_error)
      |> resume
      |> run(sandbox)
    }
  }
}

fn code(i) {
  let source = ir.integer(i)
  // |> ir.map_annotation(fn(_) { [] })
  #(cid_from_tree(source), source)
}

pub fn random_code() {
  code(int.random(1_000_000))
}

fn hash_sha256(bytes) {
  continuation.return(crypto.hash(crypto.Sha256, bytes))
}

pub fn cid_from_tree(source: ir.Node(_)) -> v1.Cid {
  cid.from_tree(source, hash_sha256)(fn(x) { x })
}
