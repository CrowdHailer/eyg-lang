//// Real Nix fixed-output verification; requires Docker and a compiled EYG binary.

import eyg/ir/dag_json
import eyg/ir/tree as ir
import filepath
import glasshouse/bundle
import glasshouse/sha256
import glasshouse/store
import gleam/bit_array
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import multiformats/cid/v1
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/bun/streams
import plinthx/bun/subprocess
import plinthx/node/process
import simplifile

const container = "eyg-roadmap-nix-check"

const image =
  "nixos/nix@sha256:e2fe74e96e965653c7b8f16ac64d1e56581c63c84d7fa07fb0692fd055cd06b0"

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let root = filepath.join(cwd, "../..")
  let modules = modules()
  let blocks =
    list.fold(modules, store.new(), fn(blocks, module) {
      store.put_node(blocks, module, sha256.hash).0
    })
  let assert Ok(root_module) = list.last(modules)
  let cid = store.cid(dag_json.to_block(root_module), sha256.hash)
  let expected = bundle.new(v1.to_string(cid), blocks)
  let hash =
    "sha256-"
    <> bit_array.base64_encode(
      sha256.hash(<<{ bundle.to_string(expected) }:utf8>>),
      True,
    )
  let assert Ok(bun) = runtime.get()
  let assert Ok(constructor) = fetch.get_response()
  let assert Ok(service) =
    server.serve(
      bun,
      server.Options(7204, "127.0.0.1", fn(request) {
        let url = fetch.request_url(request)
        let #(body, status) = case
          list.find(modules, fn(module) {
            string.ends_with(
              url,
              "/modules/"
                <> v1.to_string(store.cid(
                dag_json.to_block(module),
                sha256.hash,
              )),
            )
          })
        {
          Ok(module) -> #(dag_json.to_block(module), 200)
          Error(_) -> #(<<"missing">>, 404)
        }
        let assert Ok(response) =
          fetch.new_response_bits(constructor, body, status, [
            #("content-type", "application/json"),
          ])
        promise.resolve(response)
      }),
    )
  let assert Ok(process) = process.get()
  let env = process.env(process)
  let assert Ok(binary) = list.key_find(env, "EYG_NIX_BIN")
  let expr = expression("#" <> v1.to_string(cid), hash)
  let workflow = {
    use started <- promise.await(
      command(bun, cwd, [
        "run",
        "-d",
        "--name",
        container,
        "--network",
        "host",
        // This Docker fixture supplies the host CLI's dynamic loader. A normal
        // Nix caller passes a CLI derivation with its runtime dependencies.
        "--mount",
        "type=bind,source=/lib64,target=/lib64,readonly",
        "--mount",
        "type=bind,source=/lib/x86_64-linux-gnu,target=/lib/x86_64-linux-gnu,readonly",
        "--mount",
        "type=bind,source=" <> root <> ",target=/workspace,readonly",
        "--mount",
        "type=bind,source="
          <> filepath.directory_name(filepath.directory_name(binary))
          <> ",target=/builder,readonly",
        image,
        "sleep",
        "infinity",
      ]),
    )
    let assert Ok(_) = started
    use built <- promise.await(nix(bun, cwd, expr))
    let assert Ok(built) = built
    let built = string.trim(built)
    use text <- promise.await(
      command(bun, cwd, ["exec", container, "cat", built]),
    )
    let assert Ok(text) = text
    let assert Ok(actual) = bundle.from_string(text, sha256.hash)
    assert actual == expected
    use negative <- promise.map(nix(
      bun,
      cwd,
      expression(
        "#" <> v1.to_string(cid),
        "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
      ),
    ))
    let assert Error(reason) = negative
    assert string.contains(reason, "hash mismatch")
    built
  }
  let outcome = workflow |> promise.map(Ok) |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use stopped <- promise.await(server.stop(service, True))
  let assert Ok(_) = stopped
  let checked = case outcome {
    Ok(path) -> {
      use cached <- promise.map(nix(bun, cwd, expr))
      case result.map(cached, string.trim) {
        Ok(cached) if path == cached -> Ok(path)
        _ -> Error("offline Nix cache returned a different output")
      }
    }
    Error(reason) -> promise.resolve(Error(string.inspect(reason)))
  }
  use checked <- promise.await(checked)
  use _ <- promise.map(command(bun, cwd, ["rm", "-f", container]))
  let assert Ok(path) = checked
  io.println(
    "PASS Nix 2.34.6: complete CID graph, rejected wrong output hash, offline cached output "
    <> path,
  )
}

fn command(bun, cwd, args) {
  let assert Ok(process) = process.get()
  let env = process.env(process)
  let assert Ok(child) =
    subprocess.spawn(
      bun,
      subprocess.Options(["docker", ..args], cwd, env, "ignore", "pipe", "pipe"),
    )
  let assert Ok(out) = subprocess.stdout(child)
  let assert Ok(err) = subprocess.stderr(child)
  let output = streams.to_text(bun, out)
  let errors = streams.to_text(bun, err)
  use exited <- promise.await(subprocess.exited(child))
  use output <- promise.await(output)
  use errors <- promise.map(errors)
  let assert Ok(output) = output
  let assert Ok(errors) = errors
  case exited {
    Ok(0) -> Ok(output)
    _ -> {
      io.print_error(errors <> output)
      Error(errors <> output)
    }
  }
}

fn nix(bun, cwd, expr) {
  command(bun, cwd, [
    "exec",
    container,
    "nix-build",
    "--no-out-link",
    "--option",
    "substituters",
    "",
    "--option",
    "sandbox",
    "false",
    "--expr",
    expr,
  ])
}

fn expression(reference, hash) {
  "let fetchEyg = import /workspace/nix/fetch-eyg.nix { eyg = builtins.path { path = /builder; name = \"eyg\"; }; }; in fetchEyg { reference = "
  <> json.to_string(json.string(reference))
  <> "; hash = "
  <> json.to_string(json.string(hash))
  <> "; hub = \"http://127.0.0.1:7204\"; }"
}

fn modules() {
  let leaf = #(ir.Integer(42), Nil)
  let leaf_id = store.cid(dag_json.to_block(leaf), sha256.hash)
  let parent = #(
    ir.Reference(ir.Pinned(ir.Release("fixture", 1, leaf_id))),
    Nil,
  )
  let parent_id = store.cid(dag_json.to_block(parent), sha256.hash)
  let root = #(
    ir.Let("dependency", #(ir.Reference(ir.Content(parent_id)), Nil), #(
      ir.Reference(ir.Content(leaf_id)),
      Nil,
    )),
    Nil,
  )
  [leaf, parent, root]
}
