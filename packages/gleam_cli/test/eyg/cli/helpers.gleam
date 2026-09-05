import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/crypto.{generate_key} as _
import eyg/cli/internal/platform
import eyg/cli/system
import eyg/hub/schema
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/crypto
import gleam/dict
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
    files: dict.Dict(String, String),
    network_state: a,
    network: fn(request.Request(BitArray), a) ->
      #(Result(response.Response(BitArray), effect.FetchError), a),
  )
}

pub fn sandbox() -> Sandbox(Nil) {
  Sandbox(
    stdin: [],
    stdout: [],
    files: dict.new(),
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
  let files = dict.merge(sandbox.files, dict.from_list(files))
  Sandbox(..sandbox, files:)
}

pub fn with_file(
  sandbox: Sandbox(a),
  path: String,
  content: String,
) -> Sandbox(a) {
  with_files(sandbox, [#(path, content)])
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

pub fn run(effect: system.Effect(a), sandbox: Sandbox(b)) -> #(a, Sandbox(b)) {
  case effect {
    system.Done(value) -> #(value, sandbox)
    system.CreateDirectory(..) -> panic as "unsupported Create Directory"
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
    system.ReadDirectory(..) -> panic as "unsupported"
    system.ReadFile(path, resume) -> {
      dict.get(sandbox.files, path)
      |> result.replace_error("missing file")
      |> resume()
      |> run(sandbox)
    }
    system.SetPermissions(..) -> panic as "unsupported"
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
      let files = dict.insert(sandbox.files, path, content)
      let sandbox = Sandbox(..sandbox, files:)
      run(resume(Ok(Nil)), sandbox)
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
