import eyg/cli/helpers
import eyg/cli/internal/ir
import eyg/cli/internal/source
import eyg/cli/share
import eyg/ir/car
import eyg/ir/dag_json
import gleam/http/request
import multiformats/cid/v1

pub fn share_simple_expression_test() {
  let sandbox =
    helpers.sandbox()
    |> helpers.save_and_return(helpers.vacant_cid_response())
  let input = source.Code("3")
  let #(output, sandbox) =
    share.execute(input, helpers.config)
    |> helpers.run(sandbox)
  assert Ok(0) == output
  assert [v1.to_string(dag_json.vacant_cid)] == sandbox.stdout
}

pub fn share_unknown_package_reference_fails_test() {
  let sandbox =
    helpers.sandbox()
    |> helpers.save_and_return(helpers.vacant_cid_response())
  let input = source.Code("@unknown")
  let #(output, _sandbox) =
    share.execute(input, helpers.config)
    |> helpers.run(sandbox)
  let assert Error(reason) = output
  assert "unknown reference: @unknown" == reason
}

pub fn share_unknown_version_reference_fails_test() {
  let sandbox =
    helpers.sandbox()
    |> helpers.save_and_return(helpers.vacant_cid_response())
  let input = source.Code("@unknown:1")
  let #(output, _sandbox) =
    share.execute(input, helpers.config)
    |> helpers.run(sandbox)
  let assert Error(reason) = output
  assert "unknown reference: @unknown:1" == reason
}

pub fn share_bundles_absolute_test() {
  let files = [
    #("/main.eyg", "import \"/lib/foo.eyg\""),
    #("/lib/foo.eyg", "\"Hi\""),
  ]
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files(files)
    |> helpers.save_and_return(helpers.vacant_cid_response())
  let input = source.File("/main.eyg")
  let #(output, sandbox) =
    share.execute(input, helpers.config)
    |> helpers.run(sandbox)
  assert Ok(0) == output
  let assert [request] = sandbox.network_state
  assert Ok(car.content_type) == request.get_header(request, "content-type")
  let assert Ok(archive) = car.decode(request.body)
  let assert [root] = archive.header.roots
  let assert [b1, b2] = archive.blocks
  assert root == b1.0
  assert dag_json.to_block(ir.string("Hi")) == b2.1
}

pub fn share_fails_unknown_import_test() {
  let files = [#("/main.eyg", "import \"/lib/foo.eyg\"")]
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, _sandbox) =
    share.execute(input, helpers.config)
    |> helpers.run(sandbox)
  let assert Error(reason) = output
  assert "unknown reference: /lib/foo.eyg" == reason
}

pub fn share_deduplicates_on_hash_test() {
  let files = [
    #(
      "/main.eyg",
      "let a = import \"/lib/foo.eyg\"
import \"/lib/bar.eyg\"",
    ),
    #("/lib/foo.eyg", "\"Hi\""),
    #("/lib/bar.eyg", "\"Hi\""),
  ]
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files(files)
    |> helpers.save_and_return(helpers.vacant_cid_response())
  let input = source.File("/main.eyg")
  let #(output, sandbox) =
    share.execute(input, helpers.config)
    |> helpers.run(sandbox)
  assert Ok(0) == output
  let assert [request] = sandbox.network_state
  assert Ok(car.content_type) == request.get_header(request, "content-type")
  let assert Ok(archive) = car.decode(request.body)
  let assert [root] = archive.header.roots
  let assert [b1, b2] = archive.blocks
  assert root == b1.0
  assert dag_json.to_block(ir.string("Hi")) == b2.1
}

pub fn share_out_of_range_import_test() {
  let files = [#("/main.eyg", "import \"../../foo.eyg\"")]
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, _sandbox) =
    share.execute(input, helpers.config)
    |> helpers.run(sandbox)
  let assert Error(message) = output
  assert "unknown reference: ../../foo.eyg" == message
}

pub fn share_fail_recursive_test() {
  let files = [#("/main.eyg", "import \"/main.eyg\"")]
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, _sandbox) =
    share.execute(input, helpers.config)
    |> helpers.run(sandbox)
  let assert Error(message) = output
  assert "unknown reference: /main.eyg" == message
}

pub fn share_fails_transitive_import_cycle_test() {
  let files = [
    #("/main.eyg", "import \"/a.eyg\""),
    #("/a.eyg", "import \"/b.eyg\""),
    #("/b.eyg", "import \"/a.eyg\""),
  ]
  let sandbox = helpers.sandbox() |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, _sandbox) =
    share.execute(input, helpers.config)
    |> helpers.run(sandbox)
  let assert Error(message) = output
  assert "unknown reference: /a.eyg" == message
}

pub fn share_fails_bad_import_test() {
  let files = [
    #("/main.eyg", "import \"/lib/foo.eyg\""),
    #("/lib/foo.eyg", ":"),
  ]
  let sandbox =
    helpers.sandbox()
    |> helpers.with_files(files)
  let input = source.File("/main.eyg")
  let #(output, _sandbox) =
    share.execute(input, helpers.config)
    |> helpers.run(sandbox)
  let assert Error(message) = output
  assert "unknown reference: /lib/foo.eyg" == message
}
