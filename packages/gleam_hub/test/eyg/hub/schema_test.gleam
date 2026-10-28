import eyg/hub/schema
import eyg/ir/dag_json
import gleam/json
import gleam/option.{None, Some}
import gleam/string

pub fn share_response_test() {
  let response = dag_json.vacant_cid
  assert Ok(response)
    == schema.share_response_encode(response)
    |> json.to_string
    |> json.parse(schema.share_response_decoder())
}

pub fn share_artifact_request_test() {
  let files = [schema.ArtifactFile("index.html", "text/html", <<"<h1>":utf8>>)]
  let encoded =
    schema.share_artifact_encode("board", files, None) |> json.to_string
  assert !string.contains(encoded, "previous")
  assert Ok(#("board", files, None))
    == json.parse(encoded, schema.share_artifact_decoder())

  let previous = schema.SharedArtifact(id: "an-id", secret: "a-secret")
  assert Ok(#("board", files, Some(previous)))
    == schema.share_artifact_encode("board", files, Some(previous))
    |> json.to_string
    |> json.parse(schema.share_artifact_decoder())
}

pub fn shared_artifact_test() {
  let shared = schema.SharedArtifact(id: "an-id", secret: "a-secret")
  assert Ok(shared)
    == schema.shared_artifact_encode(shared)
    |> json.to_string
    |> json.parse(schema.shared_artifact_decoder())
  // A share without a secret cannot be linked to a newer version.
  let assert Error(_) =
    json.parse("{\"id\":\"an-id\"}", schema.shared_artifact_decoder())
}
