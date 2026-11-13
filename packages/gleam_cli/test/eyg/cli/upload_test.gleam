import eyg/cli/helpers
import eyg/cli/record
import eyg/cli/upload
import glasshouse/archive
import gleam/bit_array
import gleam/dict
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/string
import loam/sandbox
import loam/sandbox/fs
import loam/source
import otel/codec

fn recorded() {
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_cwd("/project")
    |> sandbox.with_env("EYG_TRACE_DIR", "/traces")
    |> sandbox.with_random_values([1])
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    record.execute(
      source.Code("perform StandardOut(\"hi\")"),
      record.Block,
      helpers.config,
    )
    |> sandbox.run(sandbox)
  let assert Ok(fs.Directory(children:, ..)) =
    fs.inspect(sandbox.file_system, "/traces")
  let assert [name] = dict.keys(children)
  #("/traces/" <> name, sandbox)
}

fn langfuse(request: request.Request(BitArray), requests) {
  #(
    Ok(
      response.new(200)
      |> response.set_body(<<"{}">>),
    ),
    [request, ..requests],
  )
}

pub fn upload_without_credentials_test() {
  let #(path, sandbox) = recorded()
  let assert #(sandbox.Returned(Error(reason)), _) =
    upload.execute(path, helpers.config) |> sandbox.run(sandbox)
  assert string.contains(reason, "LANGFUSE_PUBLIC_KEY")
}

pub fn upload_sends_spans_and_links_the_archive_test() {
  let #(path, sandbox) = recorded()
  let sandbox =
    sandbox
    |> sandbox.with_env("LANGFUSE_HOST", "http://localhost:3000")
    |> sandbox.with_env("LANGFUSE_PUBLIC_KEY", "pk-lf-1")
    |> sandbox.with_env("LANGFUSE_SECRET_KEY", "sk-lf-2")
    |> sandbox.with_network(langfuse, [])
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    upload.execute(path, helpers.config) |> sandbox.run(sandbox)
  let assert [request] = sandbox.network_state
  assert request.host == "localhost"
  assert request.path == "/api/public/otel/v1/traces"
  assert list.key_find(request.headers, "authorization")
    == Ok("Basic cGstbGYtMTpzay1sZi0y")
  let assert Ok(text) = fs.read(sandbox.file_system, path)
  let assert Ok(archive) = archive.from_string(text)
  let assert [archive.Langfuse(host: "http://localhost:3000", trace_id:)] =
    archive.links
  assert list.any(sandbox.stdout, fn(line) {
    string.contains(line, "http://localhost:3000/trace/" <> trace_id)
  })
}

pub fn partial_rejection_does_not_add_a_success_link_test() {
  let #(path, sandbox) = recorded()
  let sandbox =
    sandbox
    |> sandbox.with_env("LANGFUSE_PUBLIC_KEY", "pk-test")
    |> sandbox.with_env("LANGFUSE_SECRET_KEY", "sk-test")
    |> sandbox.with_network(
      fn(_, state) {
        #(
          Ok(
            response.new(200)
            |> response.set_body(<<
              "{\"partialSuccess\":{\"rejectedSpans\":\"1\"}}",
            >>),
          ),
          state,
        )
      },
      Nil,
    )
  let assert #(sandbox.Returned(Error(reason)), sandbox) =
    upload.execute(path, helpers.config) |> sandbox.run(sandbox)
  assert string.contains(reason, "partially accepted")
  let assert Ok(text) = fs.read(sandbox.file_system, path)
  let assert Ok(archived) = archive.from_string(text)
  assert archived.links == []
}

pub fn standard_otlp_configuration_uploads_the_same_archived_spans_test() {
  let #(path, sandbox) = recorded()
  let sandbox =
    sandbox
    |> sandbox.with_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
    |> sandbox.with_env(
      "OTEL_EXPORTER_OTLP_HEADERS",
      "authorization=Basic%20test",
    )
    |> sandbox.with_network(langfuse, [])
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    upload.execute(path, helpers.config) |> sandbox.run(sandbox)
  let assert [request] = sandbox.network_state
  assert request.path == "/v1/traces"
  assert list.key_find(request.headers, "authorization") == Ok("Basic test")
  let assert Ok(text) = bit_array.to_string(request.body)
  let assert Ok(spans) = json.parse(text, codec.spans())
  assert list.length(spans) == 3
}
