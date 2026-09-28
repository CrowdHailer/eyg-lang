import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/hub/schema
import eyg/ir/car
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/http/response
import gleam/int
import gleam/json
import gleam/option.{None}
import loam/os
import loam/sandbox
import midas/continuation
import multiformats/cid/v1
import ogre/origin

const eyg_origin: client.Client = client.Client(
  origin: origin.Origin(http.Https, "eyg.run", None),
)

pub const config: config.Config = config.Config(
  client: eyg_origin,
  dirs: os.Directories(config_dir: "", cache_dir: "", data_dir: ""),
)

pub fn vacant_cid_response() {
  response.new(200)
  |> response.set_body(
    schema.share_response_encode(dag_json.vacant_cid)
    |> json.to_string
    |> bit_array.from_string,
  )
}

pub fn share_server(sandbox: sandbox.Sandbox(_)) {
  sandbox.with_network(
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
